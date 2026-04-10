import AIIslandProtocol
import Foundation

/// Structured diagnostic result for a single hook integration.
struct HookHealthReport: Equatable {
    enum Severity: Equatable {
        case error
        case info
    }

    enum Issue: Equatable, CustomStringConvertible {
        case binaryNotFound
        case binaryNotExecutable(path: String)
        case configMissing(toolDir: String)
        case configMalformedJSON(path: String)
        case staleCommandPath(recorded: String, configPath: String)
        case otherHooksDetected(names: [String])

        var description: String {
            switch self {
            case .binaryNotFound:
                "Hook binary (aibridge) not found at any candidate location."
            case .binaryNotExecutable(let path):
                "Hook binary exists but is not executable: \(path)"
            case .configMissing(let toolDir):
                "Hook config file missing. Run Install to set up hooks in \(toolDir)."
            case .configMalformedJSON(let path):
                "Config file is not valid JSON: \(path)"
            case .staleCommandPath(let recorded, let configPath):
                "Command path in \(configPath) points to missing binary: \(recorded)"
            case .otherHooksDetected(let names):
                "Other hooks coexist: \(names.joined(separator: ", "))"
            }
        }

        var severity: Severity {
            switch self {
            case .otherHooksDetected: .info
            default: .error
            }
        }

        var isAutoRepairable: Bool {
            switch self {
            case .staleCommandPath, .configMissing: true
            default: false
            }
        }
    }

    var agent: String
    var issues: [Issue]
    var binaryPath: String?
    var configPath: String?
    /// Whether the tool's directory exists on disk (even if config file is missing).
    var toolDetected: Bool

    var isHealthy: Bool { errors.isEmpty }
    var errors: [Issue] { issues.filter { $0.severity == .error } }
    var notices: [Issue] { issues.filter { $0.severity == .info } }
    var repairableIssues: [Issue] { issues.filter(\.isAutoRepairable) }
}

/// Performs health checks on hook installations.
enum HookHealthCheck {

    /// Run health checks for all supported tools.
    /// Only returns reports for tools that are detected on this system.
    static func checkAll() -> [HookHealthReport] {
        let binaryPath = resolveAibridgePath()
        return [
            checkClaude(binaryPath: binaryPath),
            checkCodex(binaryPath: binaryPath),
            checkGemini(binaryPath: binaryPath),
        ].filter(\.toolDetected)
    }

    // MARK: - Per-Agent Checks

    /// Check Claude Code hook health.
    /// Config: ~/.claude/settings.json
    /// Shape: { hooks: { EventName: [{ hooks: [{ command: "..." }] }] } }
    static func checkClaude(binaryPath: String?) -> HookHealthReport {
        let fm = FileManager.default
        let configDir = NSHomeDirectory() + "/.claude"
        let settingsPath = configDir + "/settings.json"
        // Match ClaudeCodeHook.isInstalled(): directory exists OR `claude` is on PATH
        let detected = fm.fileExists(atPath: configDir) || isCommandOnPath("claude")
        var issues = binaryIssues(binaryPath)

        guard fm.fileExists(atPath: settingsPath) else {
            if detected { issues.append(.configMissing(toolDir: configDir)) }
            return HookHealthReport(agent: "Claude Code", issues: issues, binaryPath: binaryPath, configPath: nil, toolDetected: detected)
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            issues.append(.configMalformedJSON(path: settingsPath))
            return HookHealthReport(agent: "Claude Code", issues: issues, binaryPath: binaryPath, configPath: settingsPath, toolDetected: detected)
        }

        let commands = extractClaudeCommands(from: root)
        issues.append(contentsOf: stalePathIssues(commands: commands, configPath: settingsPath, fileManager: fm))

        let others = thirdPartyNames(allCommands: commands)
        if !others.isEmpty {
            issues.append(.otherHooksDetected(names: others))
        }

        return HookHealthReport(agent: "Claude Code", issues: issues, binaryPath: binaryPath, configPath: settingsPath, toolDetected: detected)
    }

    /// Check Codex hook health.
    static func checkCodex(binaryPath: String?) -> HookHealthReport {
        checkMultiDirTool(
            agent: "Codex",
            dirCandidates: [NSHomeDirectory() + "/.codex", NSHomeDirectory() + "/.config/codex"],
            configFile: "config.json",
            extractCommands: extractCodexCommands,
            binaryPath: binaryPath
        )
    }

    /// Check Gemini hook health.
    static func checkGemini(binaryPath: String?) -> HookHealthReport {
        checkMultiDirTool(
            agent: "Gemini",
            dirCandidates: [NSHomeDirectory() + "/.gemini", NSHomeDirectory() + "/.config/gemini"],
            configFile: "settings.json",
            extractCommands: extractGeminiCommands,
            binaryPath: binaryPath
        )
    }

    /// Shared checker for tools with multiple candidate config directories.
    private static func checkMultiDirTool(
        agent: String,
        dirCandidates: [String],
        configFile: String,
        extractCommands: ([String: Any]) -> [String],
        binaryPath: String?
    ) -> HookHealthReport {
        let fm = FileManager.default
        let toolDir = dirCandidates.first { fm.fileExists(atPath: $0) }
        let detected = toolDir != nil
        let configCandidates = dirCandidates.map { $0 + "/\(configFile)" }
        let configPath = configCandidates.first { fm.fileExists(atPath: $0) }
        var issues = binaryIssues(binaryPath)

        guard let configPath else {
            if let toolDir { issues.append(.configMissing(toolDir: toolDir)) }
            return HookHealthReport(agent: agent, issues: issues, binaryPath: binaryPath, configPath: nil, toolDetected: detected)
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            issues.append(.configMalformedJSON(path: configPath))
            return HookHealthReport(agent: agent, issues: issues, binaryPath: binaryPath, configPath: configPath, toolDetected: detected)
        }

        let commands = extractCommands(root)
        issues.append(contentsOf: stalePathIssues(commands: commands, configPath: configPath, fileManager: fm))

        return HookHealthReport(agent: agent, issues: issues, binaryPath: binaryPath, configPath: configPath, toolDetected: detected)
    }

    // MARK: - Binary Resolution

    /// Resolve the aibridge binary path. Returns nil only if not found anywhere.
    /// Reuses AIIslandConstants.aibridgePath, falling back to a login shell when
    /// Constants returns a bare name (which means no absolute path was found).
    private static func resolveAibridgePath() -> String? {
        let resolved = AIIslandConstants.aibridgePath
        // If Constants found an absolute path, use it
        if resolved.contains("/") {
            return resolved
        }
        // Bare name — try login shell to get the user's full PATH
        return ShellUtils.which(resolved)
    }

    private static func isCommandOnPath(_ command: String) -> Bool {
        ShellUtils.which(command) != nil
    }

    /// Binary-level issues (not found or not executable).
    private static func binaryIssues(_ binaryPath: String?) -> [HookHealthReport.Issue] {
        guard let path = binaryPath else {
            return [.binaryNotFound]
        }
        if !FileManager.default.isExecutableFile(atPath: path) {
            return [.binaryNotExecutable(path: path)]
        }
        return []
    }

    // MARK: - Command Extraction (per-agent JSON shapes)

    /// Claude: { hooks: { EventName: [{ hooks: [{ command }] }] } }
    private static func extractClaudeCommands(from root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var commands: [String] = []
        for (_, eventValue) in hooks {
            guard let groups = eventValue as? [[String: Any]] else { continue }
            for group in groups {
                guard let hookEntries = group["hooks"] as? [[String: Any]] else { continue }
                for hook in hookEntries {
                    if let command = hook["command"] as? String {
                        commands.append(command)
                    }
                }
            }
        }
        return commands
    }

    /// Codex: { hooks: { event_name: { command } | [{ command }] } }
    private static func extractCodexCommands(from root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [String: Any] else { return [] }
        var commands: [String] = []
        for (_, eventValue) in hooks {
            if let dict = eventValue as? [String: Any],
               let command = dict["command"] as? String {
                commands.append(command)
            } else if let array = eventValue as? [[String: Any]] {
                for entry in array {
                    if let command = entry["command"] as? String {
                        commands.append(command)
                    }
                }
            }
        }
        return commands
    }

    /// Gemini: { hooks: [{ event, command }] }
    private static func extractGeminiCommands(from root: [String: Any]) -> [String] {
        guard let hooks = root["hooks"] as? [[String: Any]] else { return [] }
        return hooks.compactMap { $0["command"] as? String }
    }

    // MARK: - Stale Path Detection

    /// Check extracted commands for stale aibridge paths.
    /// Skips bare command names (no `/`) that rely on PATH resolution.
    private static func stalePathIssues(
        commands: [String],
        configPath: String,
        fileManager fm: FileManager
    ) -> [HookHealthReport.Issue] {
        var issues: [HookHealthReport.Issue] = []
        var seen: Set<String> = []

        for command in commands {
            let normalized = command.lowercased()
            guard normalized.contains("aibridge") || normalized.contains("aiisland") else { continue }

            let binaryPath = extractBinaryPath(from: command)
            guard !seen.contains(binaryPath) else { continue }
            seen.insert(binaryPath)

            // Skip bare command names — they resolve via PATH, not filesystem
            guard binaryPath.contains("/") else { continue }

            if !fm.fileExists(atPath: binaryPath) {
                issues.append(.staleCommandPath(recorded: binaryPath, configPath: configPath))
            }
        }

        return issues
    }

    /// Find third-party (non-AI Island) hook command names from Claude's config.
    private static func thirdPartyNames(allCommands: [String]) -> [String] {
        var names: Set<String> = []
        for command in allCommands {
            let normalized = command.lowercased()
            guard !normalized.contains("aibridge"),
                  !normalized.contains("aiisland"),
                  !normalized.contains("ai-island") else { continue }
            let name = extractCommandName(from: command)
            if !name.isEmpty { names.insert(name) }
        }
        return names.sorted()
    }

    // MARK: - String Helpers

    /// Extract binary path from a potentially shell-quoted command string.
    private static func extractBinaryPath(from command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespaces)

        for quote in ["'", "\""] as [Character] {
            if trimmed.first == quote,
               let endQuote = trimmed.dropFirst().firstIndex(of: quote) {
                return String(trimmed[trimmed.index(after: trimmed.startIndex)..<endQuote])
            }
        }

        return String(trimmed.prefix(while: { !$0.isWhitespace }))
    }

    /// Extract a human-readable name from a hook command.
    private static func extractCommandName(from command: String) -> String {
        let binaryPath = extractBinaryPath(from: command)
        let lastComponent = (binaryPath as NSString).lastPathComponent
        return lastComponent.isEmpty ? binaryPath : lastComponent
    }
}
