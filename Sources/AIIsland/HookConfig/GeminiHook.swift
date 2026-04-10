import AIIslandProtocol
import Foundation
import os

/// Installs hooks for Google Gemini CLI.
/// Gemini CLI stores configuration in ~/.gemini/ or ~/.config/gemini/.
struct GeminiHook: HookConfigurator {

    let toolName = "Gemini"

    private let logger = Logger(subsystem: "com.aiisland.app", category: "GeminiHook")

    /// Possible config directory locations for Gemini CLI.
    private var configDirCandidates: [String] {
        [
            NSHomeDirectory() + "/.gemini",
            NSHomeDirectory() + "/.config/gemini",
        ]
    }

    /// The resolved config directory (first existing candidate).
    private var configDir: String? {
        configDirCandidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The settings file path.
    private var settingsPath: String? {
        configDir.map { $0 + "/settings.json" }
    }

    private static let hookMarker = AIIslandConstants.hookMarker

    // MARK: - HookConfigurator

    func isInstalled() -> Bool {
        configDir != nil
    }

    func installHook() throws {
        // If no config dir exists yet, create one at the preferred location
        let dir = configDir ?? configDirCandidates[0]
        let path = dir + "/settings.json"

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var settings = (try? readJSONDict(at: path)) ?? [:]
        let aibridgePath = AIIslandConstants.aibridgePath

        // Build hooks array
        let aiIslandHooks: [[String: Any]] = [
            [
                "event": "pre_tool_use",
                "command": "\(aibridgePath) --event permission_request --session $SESSION_ID --agent gemini",
            ],
            [
                "event": "post_tool_use",
                "command": "\(aibridgePath) --event tool_result --session $SESSION_ID --agent gemini",
            ],
            [
                "event": "status",
                "command": "\(aibridgePath) --event status --session $SESSION_ID --agent gemini",
            ],
        ]

        // Merge with existing hooks
        if var existingHooks = settings["hooks"] as? [[String: Any]] {
            // Remove existing AI Island hooks
            existingHooks.removeAll { entry in
                guard let command = entry["command"] as? String else { return false }
                return command.contains(Self.hookMarker)
            }
            // Add our hooks
            existingHooks.append(contentsOf: aiIslandHooks)
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = aiIslandHooks
        }

        try writeJSONDict(settings, to: path)
        logger.info("Gemini hooks written to \(path)")
    }

    func uninstallHook() throws {
        guard let path = settingsPath,
              FileManager.default.fileExists(atPath: path) else { return }

        var settings = try readJSONDict(at: path)

        if var hooks = settings["hooks"] as? [[String: Any]] {
            hooks.removeAll { entry in
                guard let command = entry["command"] as? String else { return false }
                return command.contains(Self.hookMarker)
            }
            if hooks.isEmpty {
                settings.removeValue(forKey: "hooks")
            } else {
                settings["hooks"] = hooks
            }
        }

        try writeJSONDict(settings, to: path)
        logger.info("Gemini hooks removed from \(path)")
    }

    // aibridge path resolution is centralized in AIIslandConstants.aibridgePath
}
