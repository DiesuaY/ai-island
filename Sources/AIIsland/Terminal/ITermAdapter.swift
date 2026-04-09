import AppKit
import Foundation
import os

/// Adapter for iTerm2 — uses AppleScript to locate and focus the session containing a given PID.
enum ITermAdapter: TerminalAdapter {

    static let appBundleId = "com.googlecode.iterm2"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "ITermAdapter")

    static func jump(pid: Int) async throws {
        // First, try to get the tty for the given PID so we can match by tty
        let tty = try? await ttyForPid(pid)

        if let tty = tty {
            try await jumpByTty(tty: tty)
        } else {
            // Fallback: try to find session by iterating
            try await jumpByPidSearch(pid: pid)
        }
    }

    // MARK: - Jump Strategies

    /// Jump by matching the tty device path.
    private static func jumpByTty(tty: String) async throws {
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(tty)" then
                            select t
                            tell w to select t
                            select s
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
            throw TerminalJumpError.sessionNotFound(pid: 0)
        }
        logger.info("Jumped to iTerm2 session by tty: \(tty)")
    }

    /// Jump by searching for a PID in session names or by checking process hierarchy.
    private static func jumpByPidSearch(pid: Int) async throws {
        // Use the iTerm2 scripting API to find session by PID
        // iTerm2 sessions expose their "unique ID" and we can match via shell PID
        let script = """
        tell application "iTerm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            set sessionPid to (variable named "pid" of s) as integer
                            if sessionPid is \(pid) then
                                tell w to select t
                                select s
                                return "found"
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        return "not_found"
        """

        let result = try await runAppleScript(script)
        if result == "not_found" {
            // Last resort: just activate iTerm2
            logger.info("Could not find PID \(pid) in iTerm2, activating app")
            activateByBundleId()
        } else {
            logger.info("Jumped to iTerm2 session by PID search")
        }
    }

    // MARK: - Helpers

    /// Get the tty device path for a PID using sysctl.
    private static func ttyForPid(_ pid: Int) async throws -> String {
        let output = try await runCommand("/bin/ps", arguments: ["-p", "\(pid)", "-o", "tty="])
        let tty = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tty.isEmpty, tty != "??" else {
            throw TerminalJumpError.sessionNotFound(pid: pid)
        }
        // Convert short tty name (e.g. "ttys003") to full path
        if tty.hasPrefix("/dev/") {
            return tty
        }
        return "/dev/\(tty)"
    }
}
