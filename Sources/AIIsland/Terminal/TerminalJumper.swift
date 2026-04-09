import AppKit
import Foundation
import os

// MARK: - Terminal Adapter Protocol

protocol TerminalAdapter {
    static var appBundleId: String { get }
    static func jump(pid: Int) async throws
    static func isAvailable() -> Bool
}

extension TerminalAdapter {
    static func isAvailable() -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleId) != nil
    }

    /// Activate the app by bundle identifier as a fallback.
    static func activateByBundleId() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: appBundleId) {
            NSWorkspace.shared.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, _ in }
        }
    }

    /// Run an AppleScript string via /usr/bin/osascript and return stdout.
    @discardableResult
    static func runAppleScript(_ source: String) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown AppleScript error"
            throw TerminalJumpError.appleScriptFailed(errMsg)
        }
        return output
    }

    /// Run a shell command and return stdout.
    @discardableResult
    static func runCommand(_ executable: String, arguments: [String]) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

// MARK: - Errors

enum TerminalJumpError: LocalizedError {
    case noTerminalDetected
    case sessionNotFound(pid: Int)
    case appleScriptFailed(String)
    case adapterUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .noTerminalDetected:
            return "Could not detect the terminal application for this session."
        case .sessionNotFound(let pid):
            return "No terminal session found for PID \(pid)."
        case .appleScriptFailed(let msg):
            return "AppleScript execution failed: \(msg)"
        case .adapterUnavailable(let name):
            return "Terminal adapter for \(name) is not available."
        }
    }
}

// MARK: - Terminal Jumper

final class TerminalJumper {

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "TerminalJumper")

    /// All known adapters, ordered by specificity.
    private static let adapters: [TerminalAdapter.Type] = [
        ITermAdapter.self,
        KittyAdapter.self,
        GhosttyAdapter.self,
        WarpAdapter.self,
        AlacrittyAdapter.self,
        VSCodeAdapter.self,
        TerminalAppAdapter.self,
    ]

    /// Map of known bundle-ID prefixes/names to adapter types.
    private static let bundleIdMap: [String: TerminalAdapter.Type] = [
        "com.googlecode.iterm2": ITermAdapter.self,
        "net.kovidgoyal.kitty": KittyAdapter.self,
        "com.mitchellh.ghostty": GhosttyAdapter.self,
        "dev.warp.Warp-Stable": WarpAdapter.self,
        "io.alacritty": AlacrittyAdapter.self,
        "com.apple.Terminal": TerminalAppAdapter.self,
        "com.microsoft.VSCode": VSCodeAdapter.self,
        "com.todesktop.runtime.cursor": VSCodeAdapter.self,
        "com.codeium.windsurf": VSCodeAdapter.self,
    ]

    /// Jump to the terminal tab/session containing the given PID.
    /// - Parameters:
    ///   - pid: The process ID of the shell/agent running in the terminal.
    ///   - terminalApp: Optional hint for which terminal app (bundle ID or app name).
    static func jump(pid: Int, terminalApp: String? = nil) async {
        do {
            let adapter = try resolveAdapter(terminalApp: terminalApp, pid: pid)
            try await adapter.jump(pid: pid)
            logger.info("Jumped to PID \(pid) via \(String(describing: adapter))")
        } catch {
            logger.warning("Failed to jump to PID \(pid): \(error.localizedDescription). Falling back.")
            fallbackActivate(terminalApp: terminalApp, pid: pid)
        }
    }

    // MARK: - Resolution

    /// Resolve the correct adapter for the given terminal app hint or PID.
    private static func resolveAdapter(terminalApp: String?, pid: Int) throws -> TerminalAdapter.Type {
        // 1. Try direct bundle-ID match
        if let app = terminalApp, let adapter = bundleIdMap[app], adapter.isAvailable() {
            return adapter
        }

        // 2. Try matching by app name substring
        if let app = terminalApp?.lowercased() {
            for (_, adapter) in bundleIdMap {
                let name = String(describing: adapter).replacingOccurrences(of: "Adapter", with: "").lowercased()
                if app.contains(name) && adapter.isAvailable() {
                    return adapter
                }
            }
        }

        // 3. Try detecting from parent process chain
        if let detected = detectTerminalFromProcess(pid: pid) {
            return detected
        }

        // 4. Fall back to Terminal.app if available
        if TerminalAppAdapter.isAvailable() {
            return TerminalAppAdapter.self
        }

        throw TerminalJumpError.noTerminalDetected
    }

    /// Walk the process parent chain to find a known terminal app.
    private static func detectTerminalFromProcess(pid: Int) -> TerminalAdapter.Type? {
        let runningApps = NSWorkspace.shared.runningApplications
        let bundleIds = Set(runningApps.compactMap { $0.bundleIdentifier })

        // Check which known terminals are currently running
        for (bundleId, adapter) in bundleIdMap {
            if bundleIds.contains(bundleId) && adapter.isAvailable() {
                // Verify the PID is actually under this app by checking parent chain
                if isProcessDescendant(pid: pid, ofAppBundle: bundleId, runningApps: runningApps) {
                    return adapter
                }
            }
        }

        // If we can't determine parentage, return the first running terminal
        for (bundleId, adapter) in bundleIdMap {
            if bundleIds.contains(bundleId) && adapter.isAvailable() {
                return adapter
            }
        }

        return nil
    }

    /// Check if a PID is a descendant of a running application.
    private static func isProcessDescendant(
        pid: Int,
        ofAppBundle bundleId: String,
        runningApps: [NSRunningApplication]
    ) -> Bool {
        guard let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) else {
            return false
        }
        let appPid = app.processIdentifier

        var current = Int32(pid)
        var visited = Set<Int32>()
        while current > 1 && !visited.contains(current) {
            visited.insert(current)
            if current == appPid { return true }

            // Get parent PID via sysctl
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.size
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parentPid = info.kp_eproc.e_ppid  // swiftlint:disable:this identifier_name
            if parentPid == current { break }
            current = parentPid
        }
        return false
    }

    /// Last-resort: just activate whichever terminal app we can find.
    private static func fallbackActivate(terminalApp: String?, pid: Int) {
        if let app = terminalApp, let adapter = bundleIdMap[app] {
            adapter.activateByBundleId()
            return
        }

        // Try to find a running terminal and activate it
        let runningApps = NSWorkspace.shared.runningApplications
        for (bundleId, _) in bundleIdMap {
            if let app = runningApps.first(where: { $0.bundleIdentifier == bundleId }) {
                app.activate()
                return
            }
        }
    }
}
