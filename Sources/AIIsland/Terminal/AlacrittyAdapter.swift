import AppKit
import Foundation
import os

/// Adapter for Alacritty terminal.
/// Alacritty has no scriptable interface — we just activate the app via NSWorkspace.
enum AlacrittyAdapter: TerminalAdapter {

    static let appBundleId = "io.alacritty"

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "AlacrittyAdapter")

    static func jump(pid: Int) async throws {
        logger.info("Activating Alacritty (no scripting interface) for PID \(pid)")
        activateByBundleId()
    }
}
