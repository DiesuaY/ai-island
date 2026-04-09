import Foundation

// MARK: - Wave Type

/// The waveform shape used to synthesize a tone.
public enum WaveType: Sendable {
    case square
    case triangle
}

// MARK: - Sound Event

/// Maps app events to chiptune sound specifications.
/// Each event defines a sequence of notes with frequencies, durations, and wave type.
public enum SoundEvent: CaseIterable, Sendable {

    /// Session started -- ascending C5-E5-G5 arpeggio
    case sessionStart

    /// Session ended -- descending G5-E5-C5 arpeggio
    case sessionEnd

    /// Permission requested -- two quick attention beeps (A5-A5)
    case permissionRequest

    /// Question prompt -- rising two-note (C5-G5)
    case askPrompt

    /// Permission approved -- happy ding (G6)
    case approved

    /// Permission denied -- low buzz (C3)
    case denied

    /// Task completed successfully -- victory jingle (C5-E5-G5-C6)
    case taskComplete

    /// Error occurred -- sad descending tone (C4-Bb3)
    case error

    // MARK: - Note Specification

    /// A single note in a sound sequence.
    public struct Note: Sendable {
        /// Frequency in Hz.
        public let frequency: Double
        /// Duration in seconds.
        public let duration: Double
    }

    // MARK: - Properties

    /// The sequence of notes to play for this event.
    public var notes: [Note] {
        switch self {
        case .sessionStart:
            // C5 - E5 - G5, 50ms each
            return [
                Note(frequency: 523.25, duration: 0.05),
                Note(frequency: 659.25, duration: 0.05),
                Note(frequency: 783.99, duration: 0.05),
            ]
        case .sessionEnd:
            // G5 - E5 - C5, 50ms each
            return [
                Note(frequency: 783.99, duration: 0.05),
                Note(frequency: 659.25, duration: 0.05),
                Note(frequency: 523.25, duration: 0.05),
            ]
        case .permissionRequest:
            // A5 - A5, two quick beeps 60ms each
            return [
                Note(frequency: 880.00, duration: 0.06),
                Note(frequency: 880.00, duration: 0.06),
            ]
        case .askPrompt:
            // C5 - G5, rising question tone
            return [
                Note(frequency: 523.25, duration: 0.08),
                Note(frequency: 783.99, duration: 0.08),
            ]
        case .approved:
            // Single high G6 ding
            return [
                Note(frequency: 1567.98, duration: 0.10),
            ]
        case .denied:
            // Single low C3 buzz
            return [
                Note(frequency: 130.81, duration: 0.10),
            ]
        case .taskComplete:
            // C5 - E5 - G5 - C6 victory jingle, 80ms each
            return [
                Note(frequency: 523.25, duration: 0.08),
                Note(frequency: 659.25, duration: 0.08),
                Note(frequency: 783.99, duration: 0.08),
                Note(frequency: 1046.50, duration: 0.08),
            ]
        case .error:
            // C4 - Bb3 sad descending, 100ms each
            return [
                Note(frequency: 261.63, duration: 0.10),
                Note(frequency: 233.08, duration: 0.10),
            ]
        }
    }

    /// The waveform type for this event.
    public var waveType: WaveType {
        switch self {
        case .sessionStart, .sessionEnd, .taskComplete:
            return .triangle
        case .permissionRequest, .askPrompt, .approved:
            return .square
        case .denied, .error:
            return .square
        }
    }

    /// Total duration of the sound in seconds (sum of all notes plus gaps).
    public var totalDuration: Double {
        // Small 10ms gap between notes
        let noteDuration = notes.reduce(0.0) { $0 + $1.duration }
        let gaps = Double(max(0, notes.count - 1)) * 0.01
        return noteDuration + gaps
    }
}
