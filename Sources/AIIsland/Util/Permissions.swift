import AppKit
import Foundation
import os
import ServiceManagement

/// Utility for checking and requesting app permissions.
enum Permissions {

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "Permissions")

    // MARK: - Accessibility

    /// Check if the app has accessibility permissions (required for Accessibility API usage).
    static func isAccessibilityGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permissions.
    /// Opens System Settings to the Privacy & Security > Accessibility pane.
    /// Returns true if permissions are already granted.
    @discardableResult
    static func requestAccessibility() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        // Using the options dictionary with kAXTrustedCheckOptionPrompt triggers the system dialog
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            logger.info("Accessibility permission requested; user must grant in System Settings")
        }
        return trusted
    }

    // MARK: - Login Items

    /// Check if the app is registered as a Login Item (launches at login).
    static func isLoginItemEnabled() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // On older macOS, we can't easily check without deprecated APIs
            return false
        }
    }

    /// Register or unregister the app as a Login Item.
    /// - Parameter enabled: Whether to enable or disable launch at login.
    /// - Returns: Whether the operation succeeded.
    @discardableResult
    static func setLoginItemEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                    logger.info("Registered as login item")
                } else {
                    try SMAppService.mainApp.unregister()
                    logger.info("Unregistered as login item")
                }
                return true
            } catch {
                logger.error("Failed to \(enabled ? "register" : "unregister") login item: \(error.localizedDescription)")
                return false
            }
        } else {
            logger.warning("Login item management requires macOS 13+")
            return false
        }
    }

    // MARK: - Full Disk Access (informational)

    /// Check if the app likely has Full Disk Access.
    /// There is no official API for this; we attempt to read a protected file.
    static func hasFullDiskAccess() -> Bool {
        let testPath = NSHomeDirectory() + "/Library/Safari/Bookmarks.plist"
        return FileManager.default.isReadableFile(atPath: testPath)
    }
}
