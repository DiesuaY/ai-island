import AppKit
import Foundation

/// Utility for calculating panel positioning relative to the notch / Dynamic Island area.
enum ScreenGeometry {

    /// Whether the main screen has a notch (camera housing).
    /// On MacBooks with a notch, `safeAreaInsets.top` is greater than zero.
    static func hasNotch() -> Bool {
        guard let screen = NSScreen.main else { return false }
        return screen.safeAreaInsets.top > 0
    }

    /// Returns the rectangle of the notch area in screen coordinates, or nil if there is no notch.
    static func notchFrame() -> NSRect? {
        guard let screen = NSScreen.main else { return nil }
        let insets = screen.safeAreaInsets

        guard insets.top > 0 else { return nil }

        let screenFrame = screen.frame

        // The notch is centered horizontally in the menu bar area.
        // The menu bar height is the safe area top inset.
        let menuBarHeight = insets.top

        // Notch width is approximately 180pt on 14-inch and 210pt on 16-inch MacBook Pro.
        // We estimate by looking at the gap between safe area edges.
        // A reasonable approximation: the notch is about 180-210pt wide.
        let notchWidth: CGFloat = 180
        let notchX = screenFrame.midX - notchWidth / 2
        let notchY = screenFrame.maxY - menuBarHeight

        return NSRect(
            x: notchX,
            y: notchY,
            width: notchWidth,
            height: menuBarHeight
        )
    }

    /// Calculate the panel frame for the AI Island overlay.
    /// - Parameters:
    ///   - expanded: Whether the panel is in expanded mode (taller).
    ///   - height: The desired height of the panel content area.
    /// - Returns: The frame in screen coordinates.
    static func panelFrame(expanded: Bool, height: CGFloat) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 300, height: height)
        }

        let screenFrame = screen.frame

        if hasNotch() {
            // Position the panel centered on the notch, just below the menu bar
            let panelWidth: CGFloat = expanded ? 380 : 200
            let menuBarHeight = screen.safeAreaInsets.top

            let x = screenFrame.midX - panelWidth / 2
            // In AppKit coordinates, y=0 is bottom of screen.
            // Panel sits just below the menu bar.
            let y = screenFrame.maxY - menuBarHeight - height

            return NSRect(x: x, y: y, width: panelWidth, height: height)
        } else {
            // No notch: position at top-center of screen, below the menu bar
            let panelWidth: CGFloat = expanded ? 380 : 200
            let menuBarHeight: CGFloat = 24 // Standard menu bar height

            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - menuBarHeight - height

            return NSRect(x: x, y: y, width: panelWidth, height: height)
        }
    }
}
