import AppKit
import SwiftUI
import Combine

/// Manages the Island overlay panel: positioning, expansion, and hosting SwiftUI content.
final class IslandPanelController {

    private let panel: IslandPanel
    private let appState: AppState

    private let collapsedHeight: CGFloat = DesignTokens.pillHeight
    private let monitorHeight: CGFloat = 280
    private let approveHeight: CGFloat = 360
    private let askHeight: CGFloat = 200

    private var modeObservation: Any?

    init(appState: AppState) {
        self.appState = appState

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
        switch mode {
        case .idle:
            animateFrame(width: DesignTokens.pillWidth, height: collapsedHeight, cornerRadius: DesignTokens.pillRadius, duration: 0.25)
            panel.ignoresMouseEvents = false
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

    // MARK: - Positioning

    /// Returns the safe area top inset (notch height), or 0 if no notch.
    private func safeAreaTop(for screen: NSScreen) -> CGFloat {
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top
        }
        return 0
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let safeTop = safeAreaTop(for: screen)
        let hasNotch = safeTop > 0

        let width = DesignTokens.pillWidth
        let height = collapsedHeight
        let x = screenFrame.midX - width / 2

        // Top of panel is at screenFrame.maxY (very top of screen).
        // In macOS coordinates, y is the bottom edge of the window.
        // y = screenFrame.maxY - height places the window flush with the top.
        let y: CGFloat
        if hasNotch {
            // Panel sits in the notch: top at screen top, height = safeAreaTop (32)
            y = screenFrame.maxY - height
        } else {
            // External monitor: float at top center, just below menu bar
            let menuBarHeight: CGFloat = NSMenu.menuBarVisible() ? 24 : 0
            y = screenFrame.maxY - menuBarHeight - height - 4
        }

        let frame = NSRect(x: x, y: y, width: width, height: height)
        panel.setFrame(frame, display: true)

        // Set initial corner radius for collapsed pill
        panel.updateCornerRadius(DesignTokens.pillRadius)
    }

    // MARK: - Animation

    private func animateFrame(width: CGFloat, height: CGFloat, cornerRadius: CGFloat, duration: TimeInterval) {
        guard let screen = NSScreen.main else { return }

        let screenFrame = screen.frame
        let safeTop = safeAreaTop(for: screen)
        let hasNotch = safeTop > 0

        let x = screenFrame.midX - width / 2

        // The TOP of the panel always stays at the screen's top edge.
        // It grows downward by increasing height.
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

        // Update corner radius (not animatable via NSAnimationContext, but visually fine)
        panel.updateCornerRadius(cornerRadius)
    }
}
