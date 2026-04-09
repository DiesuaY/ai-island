import AppKit

/// Non-activating overlay panel that floats above all windows like a Dynamic Island.
final class IslandPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        configure()
    }

    private func configure() {
        // Float above everything — above menu bar so it sits in the notch
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)

        // Appear on all spaces and full-screen displays
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Transparent chrome
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false  // No shadow in collapsed mode (looks like part of notch)

        // Don't hide when app loses focus
        hidesOnDeactivate = false

        // Ignore mouse events that fall outside subviews
        ignoresMouseEvents = false

        // Allow the panel to become key for button clicks, but not activate the app
        becomesKeyOnlyIfNeeded = true

        // Rounded content view
        if let contentView = contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = DesignTokens.pillRadius
            contentView.layer?.masksToBounds = true
            contentView.layer?.backgroundColor = NSColor.black.cgColor
            // Subtle border — very thin to blend with notch
            contentView.layer?.borderColor = NSColor(
                white: 0.2,
                alpha: 0.5
            ).cgColor
            contentView.layer?.borderWidth = 0.5
        }
    }

    /// Update the corner radius (e.g., when switching between pill and expanded modes).
    func updateCornerRadius(_ radius: CGFloat) {
        contentView?.layer?.cornerRadius = radius
        // Enable shadow and slightly more visible border when expanded
        let isExpanded = radius > DesignTokens.pillRadius
        hasShadow = isExpanded
        contentView?.layer?.borderWidth = isExpanded ? 0.5 : 0
    }

    // Allow the panel to become key so buttons work
    override var canBecomeKey: Bool { true }

    // Never become main window
    override var canBecomeMain: Bool { false }
}
