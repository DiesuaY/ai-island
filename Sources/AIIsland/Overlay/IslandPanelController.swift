import AppKit
import SwiftUI
import Combine

/// Manages the Island overlay panel: positioning, expansion, and hosting SwiftUI content.
final class IslandPanelController {

    private let panel: IslandPanel
    private let appState: AppState
    private let settings: IslandSettings

    private let collapsedHeight: CGFloat = DesignTokens.pillHeight
    private let monitorHeight: CGFloat = 280
    private let approveHeight: CGFloat = 380
    private let askHeight: CGFloat = 220

    private var modeObservation: Any?
    private var screenObserver: Any?
    private var autoHideTimer: Timer?
    private var settingsObservation: Any?

    init(appState: AppState, settings: IslandSettings = .shared) {
        self.appState = appState
        self.settings = settings

        let initialRect = NSRect(x: 0, y: 0, width: DesignTokens.pillWidth, height: DesignTokens.pillHeight)
        panel = IslandPanel(contentRect: initialRect)

        let hostingView = NSHostingView(
            rootView: IslandContentView()
                .environment(appState)
        )
        hostingView.frame = panel.contentView?.bounds ?? initialRect
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(hostingView)

        positionPanel()
        startModeObservation()
        observeScreenChanges()
        observeScreenPreference()
    }

    // MARK: - Public

    private var isVisible = true

    func showPanel() {
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hidePanel() {
        panel.orderOut(nil)
        isVisible = false
    }

    func toggleVisibility() {
        if isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Mode Observation

    private func startModeObservation() {
        // Use a polling timer instead of withObservationTracking which can silently break.
        // Check every 0.2s — lightweight and reliable.
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let mode = self.appState.currentMode
            if mode != self.lastObservedMode {
                self.lastObservedMode = mode
                self.handleModeChange()
            }
        }
    }

    private var lastObservedMode: IslandMode = .idle

    private func handleModeChange() {
        let mode = appState.currentMode

        // Cancel any pending auto-hide when mode changes
        autoHideTimer?.invalidate()
        autoHideTimer = nil

        // Show panel if hidden (new activity arrived)
        if !isVisible && mode != .idle {
            showPanel()
        }

        switch mode {
        case .idle:
            animateFrame(width: DesignTokens.pillWidth, height: collapsedHeight, cornerRadius: DesignTokens.pillRadius, duration: 0.25)
            panel.ignoresMouseEvents = false
            scheduleAutoHideIfNeeded()
        case .monitor:
            let sessionCount = appState.sessions.count
            // Hero card ~90px + each row ~40px + header ~50px + notch 32px
            let height = collapsedHeight + 50 + 90 + CGFloat(max(sessionCount - 1, 0)) * 40 + 16
            animateFrame(width: DesignTokens.panelWidth, height: height, cornerRadius: DesignTokens.panelRadius, duration: 0.3)
            panel.ignoresMouseEvents = false
        case .approve:
            animateFrame(width: DesignTokens.approveWidth, height: approveHeight, cornerRadius: DesignTokens.panelRadius, duration: 0.3)
            // Make panel key so buttons are clickable
            panel.makeKey()
            panel.orderFrontRegardless()
        case .ask:
            let optionCount = CGFloat(appState.pendingQuestion?.options.count ?? 0)
            // Free-form (0 options) needs space for text field; options need 40px each
            let contentHeight: CGFloat = optionCount == 0 ? 120 : (80 + optionCount * 40)
            let height = min(askHeight, contentHeight)
            animateFrame(width: DesignTokens.panelWidth, height: height, cornerRadius: DesignTokens.panelRadius, duration: 0.3)
            panel.makeKey()
            panel.orderFrontRegardless()
        case .jump:
            // Notch is 32px. Content needs to render BELOW the notch.
            // 32px notch + 44px content = 76px total
            animateFrame(width: DesignTokens.panelWidth, height: collapsedHeight + 44, cornerRadius: DesignTokens.panelRadius, duration: 0.25)
            panel.ignoresMouseEvents = false
        }
    }

    // MARK: - Auto-Hide (external monitors only)

    private func scheduleAutoHideIfNeeded() {
        guard settings.autoHideEnabled else { return }
        // Only auto-hide on external monitors (no notch)
        guard let screen = targetScreen(), !ScreenGeometry.hasNotch(screen: screen) else { return }

        autoHideTimer?.invalidate()
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(settings.autoHideSeconds), repeats: false) { [weak self] _ in
            guard let self else { return }
            // Only hide if still idle
            if self.appState.currentMode == .idle {
                self.hidePanel()
            }
        }
    }

    // MARK: - Screen Change Observation

    private func observeScreenChanges() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleModeChange()
        }
    }

    // MARK: - Positioning

    /// Returns the safe area top inset (notch height), or 0 if no notch.
    private func safeAreaTop(for screen: NSScreen) -> CGFloat {
        return screen.safeAreaInsets.top
    }

    /// Resolves the target screen for the panel.
    /// Priority: user-selected screen > auto-detect (notch screen > main screen > first screen).
    private func targetScreen() -> NSScreen? {
        // If user has selected a specific screen, try to use it
        if let selected = DisplayOption.resolveScreen(for: settings.preferredScreenID) {
            return selected
        }
        // Auto: prefer a notch screen, then main, then first
        if let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            return notchScreen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Observe changes to the preferred screen setting.
    private var lastPreferredScreenID: String = ""

    private func observeScreenPreference() {
        lastPreferredScreenID = settings.preferredScreenID
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.settings.preferredScreenID != self.lastPreferredScreenID {
                self.lastPreferredScreenID = self.settings.preferredScreenID
                self.handleModeChange() // Reposition panel on the new screen
            }
        }
    }

    private func positionPanel() {
        guard let screen = targetScreen() else { return }

        let screenFrame = screen.frame
        let safeTop = safeAreaTop(for: screen)
        let hasNotch = safeTop > 0

        let width = DesignTokens.pillWidth
        let height = collapsedHeight
        let x = screenFrame.midX - width / 2

        let y: CGFloat
        if hasNotch {
            y = screenFrame.maxY - height
        } else {
            let menuBarHeight: CGFloat = NSMenu.menuBarVisible() ? 24 : 0
            y = screenFrame.maxY - menuBarHeight - height - 4
        }

        let frame = NSRect(x: x, y: y, width: width, height: height)
        panel.setFrame(frame, display: true)

        panel.updateCornerRadius(DesignTokens.pillRadius)
    }

    // MARK: - Animation

    private func animateFrame(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, duration: TimeInterval) {
        guard let screen = targetScreen() else { return }

        let screenFrame = screen.frame
        let safeTop = safeAreaTop(for: screen)
        let hasNotch = safeTop > 0

        let x = screenFrame.midX - width / 2

        let y: CGFloat
        if hasNotch {
            y = screenFrame.maxY - height
        } else {
            let menuBarHeight: CGFloat = NSMenu.menuBarVisible() ? 24 : 0
            y = screenFrame.maxY - menuBarHeight - height - 4
        }

        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(newFrame, display: true)
        }

        panel.updateCornerRadius(cornerRadius)
    }
}
