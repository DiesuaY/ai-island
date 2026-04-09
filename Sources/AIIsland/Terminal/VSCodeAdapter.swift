import AppKit
import Foundation
import os

/// Adapter for VS Code and VS Code-based editors (Cursor, Windsurf).
/// These editors have limited terminal-level scripting, so we primarily just activate the app.
enum VSCodeAdapter: TerminalAdapter {

    static let appBundleId = "com.microsoft.VSCode"

    /// All known VS Code-based editor bundle IDs.
    static let allBundleIds = [
        "com.microsoft.VSCode",
        "com.todesktop.runtime.cursor",
        "com.codeium.windsurf",
    ]

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "VSCodeAdapter")

    static func isAvailable() -> Bool {
        allBundleIds.contains { bundleId in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) != nil
        }
    }

    static func jump(pid: Int) async throws {
        // Find which VS Code variant is running with this PID
        let runningApps = NSWorkspace.shared.runningApplications
        let app = allBundleIds.compactMap { bundleId in
            runningApps.first { $0.bundleIdentifier == bundleId }
        }.first

        if let app = app {
            app.activate()
            logger.info("Activated \(app.bundleIdentifier ?? "VSCode variant") for PID \(pid)")
        } else {
            // Try activating any available VS Code variant
            for bundleId in allBundleIds {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    NSWorkspace.shared.openApplication(
                        at: url,
                        configuration: NSWorkspace.OpenConfiguration()
                    ) { _, _ in }
                    logger.info("Activated \(bundleId) for PID \(pid)")
                    return
                }
            }
            throw TerminalJumpError.adapterUnavailable("VS Code")
        }
    }
}
