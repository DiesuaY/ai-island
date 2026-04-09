import AppKit
import Foundation

/// Utility for calculating panel positioning relative to the notch / Dynamic Island area.
enum ScreenGeometry {

    /// Returns the screen that currently has the menu bar (the one with the mouse cursor
    /// or the main screen). Falls back to NSScreen.main if no screen contains the cursor.
    static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        // Find the screen containing the mouse cursor
        for screen in NSScreen.screens {
            if screen.frame.contains(mouseLocation) {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    /// Whether the given screen has a notch (camera housing).
    static func hasNotch(screen: NSScreen? = nil) -> Bool {
        let s = screen ?? activeScreen()
        guard let s else { return false }
        return s.safeAreaInsets.top > 0
    }

    /// Returns the rectangle of the notch area in screen coordinates, or nil if there is no notch.
    static func notchFrame() -> NSRect? {
        guard let screen = activeScreen() else { return nil }
        let insets = screen.safeAreaInsets

        guard insets.top > 0 else { return nil }

        let screenFrame = screen.frame
        let menuBarHeight = insets.top

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
        guard let screen = activeScreen() else {
            return NSRect(x: 0, y: 0, width: 300, height: height)
        }

        let screenFrame = screen.frame

        if hasNotch(screen: screen) {
            let panelWidth: CGFloat = expanded ? 380 : 200
            let menuBarHeight = screen.safeAreaInsets.top

            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - menuBarHeight - height

            return NSRect(x: x, y: y, width: panelWidth, height: height)
        } else {
            let panelWidth: CGFloat = expanded ? 380 : 200
            let menuBarHeight: CGFloat = 24

            let x = screenFrame.midX - panelWidth / 2
            let y = screenFrame.maxY - menuBarHeight - height

            return NSRect(x: x, y: y, width: panelWidth, height: height)
        }
    }
}
