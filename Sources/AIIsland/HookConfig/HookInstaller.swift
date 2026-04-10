import Foundation
import os

/// Orchestrates the installation of hooks for detected AI coding tools.
final class HookInstaller {

    private static let logger = Logger(subsystem: "com.aiisland.app", category: "HookInstaller")

    /// UserDefaults keys for tracking hook installation state.
    private enum Keys {
        static let installedHooksVersion = "hookInstaller.installedVersion"
        static let installedTools = "hookInstaller.installedTools"
    }

    /// The current hook configuration version. Bump this to force re-installation.
    static let hookVersion = 5

    /// All known hook configurators.
    private static let configurators: [HookConfigurator] = [
        ClaudeCodeHook(),
        CodexHook(),
        GeminiHook(),
    ]

    // MARK: - Public API

    /// Controls how aggressively hooks are installed.
    enum InstallMode {
        /// Only re-installs if hook version changed or a new tool is detected.
        case incremental
        /// Re-installs for all detected tools, skipping version check.
        case forceReinstall
        /// Creates configs even for tools that aren't installed yet.
        case bootstrap
    }

    /// Install hooks for all detected AI tools.
    /// Returns true if all installations succeeded.
    @discardableResult
    static func installAll(mode: InstallMode = .incremental) -> Bool {
        let previousVersion = UserDefaults.standard.integer(forKey: Keys.installedHooksVersion)
        let previousTools = Set(UserDefaults.standard.stringArray(forKey: Keys.installedTools) ?? [])
        let needsReinstall = mode != .incremental || previousVersion < hookVersion

        var installedTools: [String] = []
        var allSucceeded = true

        for configurator in configurators {
            let toolName = configurator.toolName

            if mode != .bootstrap {
                guard configurator.isInstalled() else {
                    logger.info("\(toolName) not detected, skipping hook installation")
                    continue
                }
            }

            let isNew = !previousTools.contains(toolName)

            if needsReinstall || isNew {
                do {
                    try configurator.installHook()
                    logger.info("Installed hook for \(toolName)")
                    installedTools.append(toolName)
                } catch {
                    logger.error("Failed to install hook for \(toolName): \(error.localizedDescription)")
                    allSucceeded = false
                }
            } else {
                logger.debug("Hook for \(toolName) already installed (version \(previousVersion))")
                installedTools.append(toolName)
            }
        }

        // Only persist the version if ALL installations succeeded
        if allSucceeded {
            UserDefaults.standard.set(hookVersion, forKey: Keys.installedHooksVersion)
        }
        UserDefaults.standard.set(installedTools, forKey: Keys.installedTools)

        logger.info("Hook installation complete. Installed: \(installedTools.joined(separator: ", "))")
        return allSucceeded
    }

    /// Remove all installed hooks.
    static func uninstallAll() {
        for configurator in configurators {
            guard configurator.isInstalled() else { continue }
            do {
                try configurator.uninstallHook()
                logger.info("Uninstalled hook for \(configurator.toolName)")
            } catch {
                logger.error("Failed to uninstall hook for \(configurator.toolName): \(error.localizedDescription)")
            }
        }

        UserDefaults.standard.removeObject(forKey: Keys.installedHooksVersion)
        UserDefaults.standard.removeObject(forKey: Keys.installedTools)
    }

    /// Check which AI tools are detected on this system.
    static func detectedTools() -> [String] {
        configurators.filter { $0.isInstalled() }.map { $0.toolName }
    }
}

// MARK: - Hook Configurator Protocol

protocol HookConfigurator {
    /// Human-readable name of the AI tool.
    var toolName: String { get }

    /// Check if the AI tool is installed on this system.
    func isInstalled() -> Bool

    /// Install the hook configuration for this tool.
    func installHook() throws

    /// Remove the hook configuration for this tool.
    func uninstallHook() throws
}

// MARK: - JSON Merge Helpers

enum JSONMergeError: LocalizedError {
    case invalidJSON(String)
    case fileWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let detail):
            return "Invalid JSON: \(detail)"
        case .fileWriteFailed(let path):
            return "Failed to write file at \(path)"
        }
    }
}

/// Read a JSON file as a mutable dictionary, or return an empty dictionary if the file doesn't exist.
func readJSONDict(at path: String) throws -> [String: Any] {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else {
        return [:]
    }

    let data = try Data(contentsOf: url)
    guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw JSONMergeError.invalidJSON("Root is not a dictionary")
    }
    return dict
}

/// Write a dictionary as pretty-printed JSON to a file, creating parent directories as needed.
func writeJSONDict(_ dict: [String: Any], to path: String) throws {
    let url = URL(fileURLWithPath: path)
    let parentDir = url.deletingLastPathComponent().path
    try FileManager.default.createDirectory(atPath: parentDir, withIntermediateDirectories: true)

    let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}
