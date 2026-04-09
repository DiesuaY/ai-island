import AVFoundation
import Foundation

// MARK: - Chiptune Engine

/// A lightweight AVAudioEngine-based chiptune synthesizer that generates
/// square and triangle wave tones programmatically. No audio files needed.
///
/// Usage:
/// ```swift
/// let engine = ChiptuneEngine()
/// engine.play(.sessionStart)
/// ```
@Observable
final class ChiptuneEngine {

    // MARK: - Public Properties

    /// Master volume (0.0 ... 1.0). Defaults to 0.7 for audibility.
    var volume: Float = 0.7 {
        didSet {
            volume = max(0, min(1, volume))
        }
    }

    /// Whether sound is muted entirely.
    var isMuted: Bool = false

    // MARK: - Private Properties

    private let audioEngine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let sampleRate: Double = 44100.0

    /// Lock-free state shared with the audio render thread.
    /// Using UnsafeMutablePointer for real-time safety (no locks in render callback).
    private let renderState = RenderState()

    // MARK: - Render State

    /// Holds the note sequence being played, accessed from the audio render thread.
    private final class RenderState: @unchecked Sendable {
        struct PlaybackInfo {
            let notes: [SoundEvent.Note]
            let waveType: WaveType
            let gapDuration: Double
            var currentNoteIndex: Int = 0
            var sampleOffset: Int = 0
            var isGap: Bool = false
            var gapSamplesRemaining: Int = 0
        }

        private let lock = NSLock()
        private var _playback: PlaybackInfo?
        private var _volume: Float = 0.3

        var playback: PlaybackInfo? {
            get { lock.withLock { _playback } }
            set { lock.withLock { _playback = newValue } }
        }

        var volume: Float {
            get { lock.withLock { _volume } }
            set { lock.withLock { _volume = newValue } }
        }

        /// Advance state from the render thread. Returns the next sample value.
        func nextSample(sampleRate: Double) -> Float {
            lock.lock()
            defer { lock.unlock() }

            guard var pb = _playback else { return 0 }

            // Handle inter-note gap
            if pb.isGap {
                pb.gapSamplesRemaining -= 1
                if pb.gapSamplesRemaining <= 0 {
                    pb.isGap = false
                    pb.currentNoteIndex += 1
                    pb.sampleOffset = 0
                }
                _playback = pb
                return 0
            }

            // Check if we've finished all notes
            guard pb.currentNoteIndex < pb.notes.count else {
                _playback = nil
                return 0
            }

            let note = pb.notes[pb.currentNoteIndex]
            let noteSamples = Int(note.duration * sampleRate)

            // Check if current note is finished
            if pb.sampleOffset >= noteSamples {
                // Insert gap before next note
                if pb.currentNoteIndex < pb.notes.count - 1 {
                    pb.isGap = true
                    pb.gapSamplesRemaining = Int(pb.gapDuration * sampleRate)
                    _playback = pb
                    return 0
                } else {
                    // All done
                    _playback = nil
                    return 0
                }
            }

            // Generate sample
            let t = Double(pb.sampleOffset) / sampleRate
            let sample = Self.generateSample(
                frequency: note.frequency,
                time: t,
                waveType: pb.waveType
            )

            // Apply a short fade-in/fade-out envelope to avoid clicks
            let fadeLength = min(100, noteSamples / 4)
            var envelope: Float = 1.0
            if pb.sampleOffset < fadeLength {
                envelope = Float(pb.sampleOffset) / Float(fadeLength)
            } else if pb.sampleOffset > noteSamples - fadeLength {
                envelope = Float(noteSamples - pb.sampleOffset) / Float(fadeLength)
            }

            pb.sampleOffset += 1
            _playback = pb
            return sample * envelope * _volume
        }

        /// Generate a single waveform sample.
        private static func generateSample(
            frequency: Double,
            time: Double,
            waveType: WaveType
        ) -> Float {
            let phase = frequency * time
            let fractional = phase - floor(phase)

            switch waveType {
            case .square:
                // Square wave: +1 for first half of period, -1 for second half
                // Slightly band-limited by softening the transition
                return fractional < 0.5 ? 0.8 : -0.8

            case .triangle:
                // Triangle wave: ramps up then down
                if fractional < 0.25 {
                    return Float(fractional * 4.0)
                } else if fractional < 0.75 {
                    return Float(2.0 - fractional * 4.0)
                } else {
                    return Float(fractional * 4.0 - 4.0)
                }
            }
        }
    }

    // MARK: - Init

    init() {
        setupAudioEngine()
    }

    deinit {
        audioEngine.stop()
    }

    // MARK: - Setup

    private func setupAudioEngine() {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!

        let node = AVAudioSourceNode { [renderState, sampleRate] _, _, frameCount, bufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let buffer = ablPointer.first,
                  let data = buffer.mData?.assumingMemoryBound(to: Float.self)
            else {
                return noErr
            }

            for frame in 0..<Int(frameCount) {
                data[frame] = renderState.nextSample(sampleRate: sampleRate)
            }

            return noErr
        }

        self.sourceNode = node
        audioEngine.attach(node)
        audioEngine.connect(node, to: audioEngine.mainMixerNode, format: format)

        do {
            try audioEngine.start()
            NSLog("[ChiptuneEngine] Audio engine started successfully")
        } catch {
            NSLog("[ChiptuneEngine] Failed to start audio engine: \(error)")
        }
    }

    // MARK: - Playback

    /// Play a sound event. If another sound is already playing, it is replaced.
    func play(_ event: SoundEvent) {
        guard !isMuted else {
            NSLog("[ChiptuneEngine] Muted, skipping \(event)")
            return
        }

        NSLog("[ChiptuneEngine] Playing \(event), engine running: \(audioEngine.isRunning), volume: \(volume)")

        // Ensure the engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                NSLog("[ChiptuneEngine] Restarted audio engine")
            } catch {
                NSLog("[ChiptuneEngine] Failed to restart audio engine: \(error)")
                return
            }
        }

        renderState.volume = volume
        renderState.playback = RenderState.PlaybackInfo(
            notes: event.notes,
            waveType: event.waveType,
            gapDuration: 0.01
        )
    }

    /// Stop any currently playing sound immediately.
    func stopPlayback() {
        renderState.playback = nil
    }

    // MARK: - Convenience Methods

    /// Play the session start arpeggio.
    func playSessionStart() { play(.sessionStart) }

    /// Play the session end arpeggio.
    func playSessionEnd() { play(.sessionEnd) }

    /// Play the permission request attention tone.
    func playPermissionRequest() { play(.permissionRequest) }

    /// Play the question/ask prompt tone.
    func playAskPrompt() { play(.askPrompt) }

    /// Play the approval ding.
    func playApproved() { play(.approved) }

    /// Play the denial buzz.
    func playDenied() { play(.denied) }

    /// Play the task complete victory jingle.
    func playTaskComplete() { play(.taskComplete) }

    /// Play the error tone.
    func playError() { play(.error) }
}
