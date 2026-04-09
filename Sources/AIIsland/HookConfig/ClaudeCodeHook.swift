import AIIslandProtocol
import Foundation
import os

/// Installs hooks into Claude Code's ~/.claude/settings.json.
/// Uses the same pattern as open-vibe-island: one hook per event, --source claude.
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

    /// Permission request hooks get 24 hours for user response.
    private static let permissionTimeout = 86_400

    /// All Claude Code hook events to install.
    private static let eventSpecs: [(name: String, matcher: String?, timeout: Int?)] = [
        ("UserPromptSubmit", nil, nil),
        ("SessionStart", nil, nil),
        ("SessionEnd", nil, nil),
        ("Stop", nil, nil),
        ("StopFailure", nil, nil),
        ("SubagentStart", nil, nil),
        ("SubagentStop", nil, nil),
        ("Notification", "*", nil),
        ("PreToolUse", "*", nil),
        ("PermissionRequest", "*", permissionTimeout),
        ("PostToolUse", "*", nil),
        ("PostToolUseFailure", "*", nil),
        ("PermissionDenied", "*", nil),
        ("PreCompact", nil, nil),
    ]

    // MARK: - HookConfigurator

    func isInstalled() -> Bool {
        if FileManager.default.fileExists(atPath: configDir) {
            return true
        }
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
        let fm = FileManager.default

        // Ensure ~/.claude directory exists
        if !fm.fileExists(atPath: configDir) {
            try fm.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }

        // Write the statusline script first (installSettingsJSON references its path)
        try installStatuslineScript()

        let existingData: Data? = fm.fileExists(atPath: settingsPath)
            ? try Data(contentsOf: URL(fileURLWithPath: settingsPath))
            : nil

        let hookCommand = buildHookCommand()
        let updatedData = try installSettingsJSON(existingData: existingData, hookCommand: hookCommand)

        if let data = updatedData {
            try data.write(to: URL(fileURLWithPath: settingsPath))
            logger.info("Claude Code hooks written to \(settingsPath)")
        }
    }

    func uninstallHook() throws {
        guard FileManager.default.fileExists(atPath: settingsPath) else { return }

        var settings = try readJSONDict(at: settingsPath)
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for spec in Self.eventSpecs {
            let existingGroups = hooks[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitize(groups: existingGroups)

            if cleanedGroups.isEmpty {
                hooks.removeValue(forKey: spec.name)
            } else {
                hooks[spec.name] = cleanedGroups
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }

        // Remove statusline if it points to our script
        if let sl = settings["statusLine"] as? [String: Any],
           let cmd = sl["command"] as? String,
           cmd.contains(".aiisland/statusline.sh") {
            settings.removeValue(forKey: "statusLine")
        }

        try writeJSONDict(settings, to: settingsPath)
        logger.info("Claude Code hooks removed from \(settingsPath)")

        // Clean up statusline script
        try? FileManager.default.removeItem(atPath: statuslineScriptPath)
    }

    // MARK: - Statusline

    /// The statusline script path.
    private var statuslineScriptPath: String {
        AIIslandConstants.socketDir + "/statusline.sh"
    }

    /// Write the statusline shell script to ~/.aiisland/statusline.sh.
    /// The script caches usage JSON for AI Island, then auto-detects and chains to
    /// claude-hud (or any other Node.js statusline plugin) if installed.
    private func installStatuslineScript() throws {
        let fm = FileManager.default
        let dir = AIIslandConstants.socketDir
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        let cachePath = AIIslandConstants.statusCachePath
        let script = """
        #!/bin/bash
        # AI Island statusline script — caches Claude Code usage data.
        # Receives statusline JSON on stdin, caches it, then forwards to claude-hud if installed.
        INPUT=$(cat)
        echo "$INPUT" > "\(cachePath)"
        # Chain to claude-hud if installed
        plugin_dir=$(ls -d "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/claude-hud/claude-hud/*/ 2>/dev/null | awk -F/ '{ print $(NF-1) "\\t" $0 }' | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1 | cut -f2-)
        if [ -n "$plugin_dir" ]; then
            runtime=$(command -v bun 2>/dev/null || command -v node 2>/dev/null)
            if [ -n "$runtime" ]; then
                if [ "$(basename "$runtime")" = "bun" ]; then
                    source="src/index.ts"
                else
                    source="dist/index.js"
                fi
                echo "$INPUT" | "$runtime" "${plugin_dir}${source}"
            fi
        fi
        """

        try script.write(toFile: statuslineScriptPath, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: statuslineScriptPath)

        logger.info("Statusline script installed at \(statuslineScriptPath)")
    }

    // MARK: - Hook Command

    /// Build the hook command: path to aibridge with --source claude
    private func buildHookCommand() -> String {
        let path = AIIslandConstants.aibridgePath
        return "\(shellQuote(path)) --source claude"
    }

    // MARK: - Settings JSON Manipulation

    private func installSettingsJSON(existingData: Data?, hookCommand: String) throws -> Data? {
        var rootObject = try loadRootObject(from: existingData)
        let existingHooksObject = rootObject["hooks"] as? [String: Any] ?? [:]
        var hooksObject: [String: Any] = [:]

        // Preserve non-AI-Island hooks from all event types
        for (eventName, value) in existingHooksObject {
            let existingGroups = value as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups)
            if !cleanedGroups.isEmpty {
                hooksObject[eventName] = cleanedGroups
            }
        }

        // Add our managed hooks for each event
        for spec in Self.eventSpecs {
            let existingGroups = hooksObject[spec.name] as? [Any] ?? []
            let cleanedGroups = sanitizeForInstall(groups: existingGroups)
            hooksObject[spec.name] = cleanedGroups + [managedGroup(matcher: spec.matcher, timeout: spec.timeout, hookCommand: hookCommand)]
        }

        rootObject["hooks"] = hooksObject

        // Also set the statusline command so settings.json is written only once
        rootObject["statusLine"] = [
            "type": "command",
            "command": statuslineScriptPath,
        ]

        return try JSONSerialization.data(withJSONObject: rootObject, options: [.prettyPrinted, .sortedKeys])
    }

    private func managedGroup(matcher: String?, timeout: Int?, hookCommand: String) -> [String: Any] {
        var hook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout {
            hook["timeout"] = timeout
        }

        var group: [String: Any] = [
            "hooks": [hook],
        ]
        if let matcher {
            group["matcher"] = matcher
        }

        return group
    }

    // MARK: - Sanitization (remove old AI Island hooks)

    /// Remove AI Island hooks, keep user hooks.
    private func sanitize(groups: [Any]) -> [[String: Any]] {
        groups.compactMap { item in
            guard var group = item as? [String: Any] else { return nil }

            let existingHooks = group["hooks"] as? [Any] ?? []
            let filteredHooks = existingHooks.compactMap { hook -> [String: Any]? in
                guard let hook = hook as? [String: Any] else { return nil }
                return isAIIslandHook(hook) ? nil : hook
            }

            guard !filteredHooks.isEmpty else { return nil }
            group["hooks"] = filteredHooks
            return group
        }
    }

    /// Remove AI Island hooks during install (same as sanitize).
    private func sanitizeForInstall(groups: [Any]) -> [[String: Any]] {
        sanitize(groups: groups)
    }

    /// Check if a hook entry was installed by AI Island.
    private func isAIIslandHook(_ hook: [String: Any]) -> Bool {
        guard let command = hook["command"] as? String else { return false }
        let normalized = command.lowercased()
        return normalized.contains(Self.hookMarker)
            || normalized.contains("aiisland")
            || normalized.contains("ai-island")
    }

    // MARK: - Helpers

    private func loadRootObject(from data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        let object = try JSONSerialization.jsonObject(with: data)
        guard let rootObject = object as? [String: Any] else {
            throw NSError(domain: "ClaudeCodeHook", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid settings.json"])
        }
        return rootObject
    }

    private func shellQuote(_ string: String) -> String {
        guard !string.isEmpty else { return "''" }
        return "'\(string.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
