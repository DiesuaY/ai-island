import AIIslandProtocol
import Foundation
import os

/// Installs hooks into Claude Code's ~/.claude/settings.json.
/// Hooks notify AI Island about tool use events, permission requests, and status changes.
struct ClaudeCodeHook: HookConfigurator {

    let toolName = "Claude Code"

    private let logger = Logger(subsystem: "com.aiisland.app", category: "ClaudeCodeHook")

    /// The Claude Code settings directory.
    private var configDir: String {
        NSHomeDirectory() + "/.claude"
    }

    /// The settings file path.
    private var settingsPath: String {
        configDir + "/settings.json"
    }

    /// Marker to identify hooks installed by AI Island.
    private static let hookMarker = "aibridge"

    // MARK: - HookConfigurator

    func isInstalled() -> Bool {
        // Check if ~/.claude directory exists, or create it so hooks can be bootstrapped
        if FileManager.default.fileExists(atPath: configDir) {
            return true
        }
        // Also check if the `claude` command is available in PATH
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["claude"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    func installHook() throws {
        var settings = try readJSONDict(at: settingsPath)

        // Build the hooks dictionary
        let hooks = buildHooksConfig()

        // Merge with existing hooks — preserve user hooks, replace AI Island hooks
        if var existingHooks = settings["hooks"] as? [String: Any] {
            for (eventType, newHookEntries) in hooks {
                if var existingEntries = existingHooks[eventType] as? [[String: Any]] {
                    // Remove any existing AI Island hooks
                    existingEntries.removeAll { entry in
                        isAIIslandHook(entry)
                    }
                    // Add our hooks
                    if let newEntries = newHookEntries as? [[String: Any]] {
                        existingEntries.append(contentsOf: newEntries)
                    }
                    existingHooks[eventType] = existingEntries
                } else {
                    existingHooks[eventType] = newHookEntries
                }
            }
            settings["hooks"] = existingHooks
        } else {
            settings["hooks"] = hooks
        }

        try writeJSONDict(settings, to: settingsPath)
        logger.info("Claude Code hooks written to \(settingsPath)")
    }

    func uninstallHook() throws {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return }

        var settings = try readJSONDict(at: settingsPath)

        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (eventType, entries) in hooks {
            if var entryList = entries as? [[String: Any]] {
                entryList.removeAll { isAIIslandHook($0) }
                if entryList.isEmpty {
                    hooks.removeValue(forKey: eventType)
                } else {
                    hooks[eventType] = entryList
                }
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        try writeJSONDict(settings, to: settingsPath)
        logger.info("Claude Code hooks removed from \(settingsPath)")
    }

    // MARK: - Hook Configuration

    /// Build the Claude Code hooks configuration dictionary.
    ///
    /// Claude Code pipes JSON on stdin to hook commands. The aibridge binary
    /// reads stdin natively, so we use `cat |` to ensure the pipe stays open.
    /// `$PPID` is the parent PID (the Claude Code process), stable across all hooks in a session.
    private func buildHooksConfig() -> [String: Any] {
        let aibridgePath = AIIslandConstants.aibridgePath

        return [
            "PreToolUse": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "cat | \(aibridgePath) --event permission_request --session \"claude-$PPID\" --agent claude --terminal-pid $PPID"
                        ]
                    ]
                ] as [String: Any]
            ],
            "PostToolUse": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "cat | \(aibridgePath) --event tool_result --session \"claude-$PPID\" --agent claude --terminal-pid $PPID"
                        ]
                    ]
                ] as [String: Any]
            ],
            "Notification": [
                [
                    "matcher": "",
                    "hooks": [
                        [
                            "type": "command",
                            "command": "cat | \(aibridgePath) --event status --session \"claude-$PPID\" --agent claude --terminal-pid $PPID"
                        ]
                    ]
                ] as [String: Any]
            ],
        ]
    }

    /// Check if a hook entry was installed by AI Island.
    private func isAIIslandHook(_ entry: [String: Any]) -> Bool {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return false }
        return hooks.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(Self.hookMarker)
        }
    }
}
