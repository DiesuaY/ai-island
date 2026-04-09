import AppKit
import Foundation
import os

/// Adapter for Ghostty terminal.
/// Ghostty 1.3+ supports --class for window identification.
/// Falls back to simple app activation since Ghostty has limited scripting support.
enum GhosttyAdapter: TerminalAdapter {

    static let appBundleId = "com.mitchellh.ghostty"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "GhosttyAdapter")

    static func jump(pid: Int) async throws {
        // Ghostty does not have AppleScript support or a remote-control protocol like kitty.
        // Attempt to use accessibility APIs if available, otherwise just activate.
        if await tryAccessibilityFocus(pid: pid) {
            logger.info("Focused Ghostty window via accessibility for PID \(pid)")
            return
        }

        // Fallback: activate the app
        logger.info("Activating Ghostty app (no tab-level jump available) for PID \(pid)")
        activateByBundleId()
    }

    // MARK: - Accessibility Focus

    /// Try to find and focus the Ghostty window containing the PID using Accessibility APIs.
    private static func tryAccessibilityFocus(pid: Int) async -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let runningApps = NSWorkspace.shared.runningApplications
        guard let ghosttyApp = runningApps.first(where: { $0.bundleIdentifier == appBundleId }) else {
            return false
        }

        let appElement = AXUIElementCreateApplication(ghosttyApp.processIdentifier)

        // Get all windows
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            return false
        }

        // Try to find the window with a title containing the PID or its tty
        let tty = try? await ttyNameForPid(pid)

        for window in windows {
            var titleRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef) == .success,
                  let title = titleRef as? String else {
                continue
            }

            let matchesTty = tty.map { title.contains($0) } ?? false
            let matchesPid = title.contains("\(pid)")

            if matchesTty || matchesPid {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                ghosttyApp.activate()
                return true
            }
        }

        // If we couldn't match a specific window, just activate the app
        ghosttyApp.activate()
        return true
    }

    private static func ttyNameForPid(_ pid: Int) async throws -> String {
        let output = try await runCommand("/bin/ps", arguments: ["-p", "\(pid)", "-o", "tty="])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
