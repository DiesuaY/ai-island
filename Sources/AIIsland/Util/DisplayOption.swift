import AppKit

/// Represents a selectable display for the overlay panel.
struct DisplayOption: Identifiable, Hashable {
    let id: String          // "display-{screenNumber}" or "" for auto
    let title: String       // e.g., "Built-in Retina Display"
    let subtitle: String    // e.g., "Notch detected" or "2560×1440"
    let hasNotch: Bool

    /// Auto-detect option (notch screen > main screen > first screen).
    static let auto = DisplayOption(id: "", title: "Automatic", subtitle: "Prefer notch screen", hasNotch: false)

    /// Enumerates all connected screens as display options.
    static func allScreenOptions() -> [DisplayOption] {
        var options: [DisplayOption] = [.auto]
        for screen in NSScreen.screens {
            let screenID = screenIdentifier(for: screen)
            let name = screen.localizedName
            let hasNotch = screen.safeAreaInsets.top > 0
            let size = screen.frame.size
            let subtitle = hasNotch
                ? "Notch detected"
                : "\(Int(size.width))×\(Int(size.height))"
            options.append(DisplayOption(
                id: screenID,
                title: name,
                subtitle: subtitle,
                hasNotch: hasNotch
            ))
        }
        return options
    }

    /// Resolve the preferred screen from a screen ID. Returns nil for auto.
    static func resolveScreen(for screenID: String) -> NSScreen? {
        guard !screenID.isEmpty else { return nil }
        return NSScreen.screens.first { screenIdentifier(for: $0) == screenID }
    }

    /// Stable identifier for an NSScreen based on its display ID.
    static func screenIdentifier(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return "display-unknown"
        }
        return "display-\(screenNumber.uint32Value)"
    }
}
