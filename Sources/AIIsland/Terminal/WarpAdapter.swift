import AppKit
import Foundation
import os

/// Adapter for Warp terminal.
/// Warp has limited AppleScript/automation support, so we just activate the app.
enum WarpAdapter: TerminalAdapter {

    static let appBundleId = "dev.warp.Warp-Stable"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "WarpAdapter")

    static func jump(pid: Int) async throws {
        // Warp does not expose AppleScript or remote-control APIs for tab/session navigation.
        // The best we can do is activate the app.
        logger.info("Activating Warp (no tab-level jump available) for PID \(pid)")
        activateByBundleId()
    }
}
