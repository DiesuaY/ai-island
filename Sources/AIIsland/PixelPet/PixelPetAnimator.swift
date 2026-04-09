import SwiftUI
import Combine

// MARK: - Pixel Pet Animator

/// Drives the two-frame animation for a pixel pet.
/// Alternates between frame1 and frame2 at ~2fps when active.
/// Pauses animation when the session status is idle or done.
@Observable
final class PixelPetAnimator {

    // MARK: - Public State

    /// The species being animated.
    var species: PetSpecies

    /// Current session status, used to decide whether to animate.
    var status: SessionStatus = .idle

    /// The pixel grid that should be rendered right now.
    var currentFrame: [[Bool]] {
        showingFrame1 ? species.frame1 : species.frame2
    }

    // MARK: - Private

    private var showingFrame1: Bool = true
    private var timer: Timer?

    // MARK: - Init

    init(species: PetSpecies = .cat) {
        self.species = species
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Lifecycle

    /// Start the animation timer. Call when the view appears.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick()
        }
    }

    /// Stop the animation timer. Call when the view disappears.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func tick() {
        // Pause animation when idle or done -- show frame1 as resting pose
        guard shouldAnimate else {
            if !showingFrame1 {
                showingFrame1 = true
            }
            return
        }
        showingFrame1.toggle()
    }

    /// Determines whether the pet should be animated based on status.
    private var shouldAnimate: Bool {
        switch status {
        case .idle, .done:
            return false
        case .working, .waitingApproval, .waitingAnswer, .error:
            return true
        }
    }
}

// MARK: - Animated Pet View (convenience)

/// A self-animating pixel pet view that manages its own animator.
struct AnimatedPixelPetView: View {
    let species: PetSpecies
    let status: SessionStatus
    var size: CGFloat = 32

    @State private var animator: PixelPetAnimator

    init(species: PetSpecies, status: SessionStatus, size: CGFloat = 32) {
        self.species = species
        self.status = status
        self.size = size
        self._animator = State(initialValue: PixelPetAnimator(species: species))
    }

    var body: some View {
        PixelPetView(
            grid: animator.currentFrame,
            status: status,
            species: species,
            size: size
        )
        .onAppear {
            animator.species = species
            animator.status = status
            animator.start()
        }
        .onDisappear {
            animator.stop()
        }
        .onChange(of: status) { _, newStatus in
            animator.status = newStatus
        }
    }
}
