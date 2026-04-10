import AIIslandProtocol
import Foundation
import os

/// Installs hooks for OpenAI Codex CLI.
/// Codex stores configuration in ~/.codex/ or ~/.config/codex/.
struct CodexHook: HookConfigurator {

    let toolName = "Codex"

    private let logger = Logger(subsystem: "com.aiisland.app", category: "CodexHook")

    /// Possible config directory locations for Codex CLI.
    private var configDirCandidates: [String] {
        [
            NSHomeDirectory() + "/.codex",
            NSHomeDirectory() + "/.config/codex",
        ]
    }

    /// The resolved config directory (first existing candidate).
    private var configDir: String? {
        configDirCandidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The hooks config file path.
    private var configPath: String? {
        configDir.map { $0 + "/config.json" }
    }

    private static let hookMarker = AIIslandConstants.hookMarker

    // MARK: - HookConfigurator

    func isInstalled() -> Bool {
        configDir != nil
    }

    func installHook() throws {
        // If no config dir exists yet, create one at the preferred location
        let dir = configDir ?? configDirCandidates[0]
        let path = dir + "/config.json"

        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        var config = (try? readJSONDict(at: path)) ?? [:]
        let aibridgePath = AIIslandConstants.aibridgePath

        // Codex CLI uses a "hooks" key with event-based commands
        var hooks = config["hooks"] as? [String: Any] ?? [:]

        let hookEntries: [String: Any] = [
            "pre_tool_use": [
                "command": "\(aibridgePath) --event permission_request --session $SESSION_ID --agent codex"
            ],
            "post_tool_use": [
                "command": "\(aibridgePath) --event tool_result --session $SESSION_ID --agent codex"
            ],
            "on_status": [
                "command": "\(aibridgePath) --event status --session $SESSION_ID --agent codex"
            ],
        ]

        // Merge: replace AI Island hooks, preserve others
        for (key, value) in hookEntries {
            if let existingArray = hooks[key] as? [[String: Any]] {
                // Already an array — filter out AI Island entries and append ours
                var filtered = existingArray.filter { entry in
                    guard let command = entry["command"] as? String else { return true }
                    return !command.contains(Self.hookMarker)
                }
                filtered.append(value as! [String: Any])
                hooks[key] = filtered
            } else if let existingDict = hooks[key] as? [String: Any] {
                // Single dictionary — check if it's ours or the user's
                if let command = existingDict["command"] as? String,
                   command.contains(Self.hookMarker) {
                    // Replace our old hook
                    hooks[key] = value
                } else {
                    // User's hook — wrap both in an array
                    hooks[key] = [existingDict, value]
                }
            } else {
                // No existing hook — set directly
                hooks[key] = value
            }
        }

        config["hooks"] = hooks
        try writeJSONDict(config, to: path)
        logger.info("Codex hooks written to \(path)")
    }

    func uninstallHook() throws {
        guard let path = configPath,
              FileManager.default.fileExists(atPath: path) else { return }

        var config = try readJSONDict(at: path)
        guard var hooks = config["hooks"] as? [String: Any] else { return }

        let keysToCheck = ["pre_tool_use", "post_tool_use", "on_status"]
        for key in keysToCheck {
            if let entry = hooks[key] as? [String: Any],
               let command = entry["command"] as? String,
               command.contains(Self.hookMarker) {
                hooks.removeValue(forKey: key)
            } else if let entries = hooks[key] as? [[String: Any]] {
                let filtered = entries.filter { entry in
                    guard let command = entry["command"] as? String else { return true }
                    return !command.contains(Self.hookMarker)
                }
                if filtered.isEmpty {
                    hooks.removeValue(forKey: key)
                } else if filtered.count == 1 {
                    hooks[key] = filtered[0]
                } else {
                    hooks[key] = filtered
                }
            }
        }

        if hooks.isEmpty {
            config.removeValue(forKey: "hooks")
        } else {
            config["hooks"] = hooks
        }

        try writeJSONDict(config, to: path)
        logger.info("Codex hooks removed from \(path)")
    }

    // aibridge path resolution is centralized in AIIslandConstants.aibridgePath
}
