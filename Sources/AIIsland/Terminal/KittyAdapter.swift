import AppKit
import Foundation
import os

/// Adapter for Kitty terminal.
/// Kitty has excellent remote control support via `kitty @` commands.
enum KittyAdapter: TerminalAdapter {

    static let appBundleId = "net.kovidgoyal.kitty"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "KittyAdapter")

    static func jump(pid: Int) async throws {
        // Use kitty's remote control to focus the window matching the PID
        let kittyPath = kittyExecutablePath()

        do {
            try await runCommand(kittyPath, arguments: [
                "@", "focus-window", "--match", "pid:\(pid)"
            ])
            logger.info("Focused kitty window for PID \(pid) via remote control")
        } catch {
            // The remote control command may fail if:
            // - Remote control is not enabled (allow_remote_control in kitty.conf)
            // - The PID doesn't match any window
            logger.warning("kitty @ focus-window failed: \(error.localizedDescription). Trying fallback.")

            // Try focusing by the shell's child PID (the agent process)
            do {
                try await runCommand(kittyPath, arguments: [
                    "@", "focus-window", "--match", "recent:0"
                ])
            } catch {
                // Last resort: just activate the app
                logger.info("Activating Kitty app for PID \(pid)")
            }

            activateByBundleId()
        }
    }

    // MARK: - Helpers

    /// Find the kitty executable path.
    private static func kittyExecutablePath() -> String {
        // Common installation paths
        let candidates = [
            "/Applications/kitty.app/Contents/MacOS/kitty",
            "/usr/local/bin/kitty",
            "/opt/homebrew/bin/kitty",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fall back to hoping it's in PATH
        return "/usr/local/bin/kitty"
    }
}
