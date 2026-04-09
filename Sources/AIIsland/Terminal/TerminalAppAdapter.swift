import AppKit
import Foundation
import os

/// Adapter for macOS Terminal.app — uses AppleScript to find and focus the tab with the matching process.
enum TerminalAppAdapter: TerminalAdapter {

    static let appBundleId = "com.apple.Terminal"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "TerminalAppAdapter")

    static func jump(pid: Int) async throws {
        // Get the tty for the PID, then find the Terminal.app tab with that tty
        let tty = try await ttyForPid(pid)

        let script = """
        tell application "Terminal"
            activate
            set targetTty to "\(tty)"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is targetTty then
                        set selected of t to true
                        set index of w to 1
                        return "found"
                    end if
                end repeat
            end repeat
        end tell
        return "not_found"
        """

        let result = try await runAppleScript(script)
        if result == "not_found" {
            // Fall back to searching by process name in tab processes
            try await jumpByProcessSearch(pid: pid)
        } else {
            logger.info("Jumped to Terminal.app tab by tty: \(tty)")
        }
    }

    // MARK: - Fallback

    /// Search tabs by checking if the PID appears in the tab's processes.
    private static func jumpByProcessSearch(pid: Int) async throws {
        let script = """
        tell application "Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    set procs to processes of t
                    repeat with p in procs
                        if p contains "\(pid)" then
                            set selected of t to true
                            set index of w to 1
                            return "found"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return "not_found"
        """

        let result = try await runAppleScript(script)
        if result == "not_found" {
            logger.info("Could not find PID \(pid) in Terminal.app, activating app")
            activateByBundleId()
        } else {
            logger.info("Jumped to Terminal.app tab by process search")
        }
    }

    // MARK: - Helpers

    private static func ttyForPid(_ pid: Int) async throws -> String {
        let output = try await runCommand("/bin/ps", arguments: ["-p", "\(pid)", "-o", "tty="])
        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??" else {
            throw TerminalJumpError.sessionNotFound(pid: pid)
        }
        if tty.hasPrefix("/dev/") {
            return tty
        }
        return "/dev/\(tty)"
    }
}
