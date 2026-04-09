import Foundation

// MARK: - Generic JSON Value

/// A type-erased JSON value for passing arbitrary Claude hook data (tool_input, tool_response, etc.)
public enum HookJSONValue: Equatable, Codable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: HookJSONValue])
    case array([HookJSONValue])
    case null

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: HookJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([HookJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .boolean(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Access a string value from an object by key.
    public func stringValue(forKey key: String) -> String? {
        guard case let .object(dict) = self, case let .string(value)? = dict[key] else { return nil }
        return value
    }
}

// MARK: - Hook Event Name

public enum ClaudeHookEventName: String, Codable, Sendable {
    case sessionStart = "SessionStart"
    case sessionEnd = "SessionEnd"
    case userPromptSubmit = "UserPromptSubmit"
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case postToolUseFailure = "PostToolUseFailure"
    case permissionRequest = "PermissionRequest"
    case permissionDenied = "PermissionDenied"
    case notification = "Notification"
    case stop = "Stop"
    case stopFailure = "StopFailure"
    case subagentStart = "SubagentStart"
    case subagentStop = "SubagentStop"
    case preCompact = "PreCompact"
}

// MARK: - Permission Mode

public enum ClaudePermissionMode: String, Codable, Sendable {
    case `default`
    case acceptEdits
    case plan
    case dontAsk
    case bypassPermissions
}

// MARK: - Permission Behavior

public enum ClaudePermissionBehavior: String, Codable, Sendable {
    case allow
    case deny
    case ask
}

// MARK: - Permission Update Destination

public enum ClaudePermissionUpdateDestination: String, Codable, Sendable {
    case userSettings
    case projectSettings
    case localSettings
    case session
    case cliArg
}

// MARK: - Permission Rule Value

public struct ClaudePermissionRuleValue: Equatable, Codable, Sendable {
    public var toolName: String
    public var ruleContent: String?

    public init(toolName: String, ruleContent: String? = nil) {
        self.toolName = toolName
        self.ruleContent = ruleContent
    }
}

// MARK: - Permission Update

public enum ClaudePermissionUpdate: Equatable, Codable, Sendable {
    case addRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case replaceRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case removeRules(destination: ClaudePermissionUpdateDestination, rules: [ClaudePermissionRuleValue], behavior: ClaudePermissionBehavior)
    case setMode(destination: ClaudePermissionUpdateDestination, mode: ClaudePermissionMode)
    case addDirectories(destination: ClaudePermissionUpdateDestination, directories: [String])
    case removeDirectories(destination: ClaudePermissionUpdateDestination, directories: [String])

    private enum CodingKeys: String, CodingKey {
        case type, destination, rules, behavior, mode, directories
    }

    private enum UpdateType: String, Codable {
        case addRules, replaceRules, removeRules, setMode, addDirectories, removeDirectories
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(UpdateType.self, forKey: .type)
        let destination = try container.decode(ClaudePermissionUpdateDestination.self, forKey: .destination)

        switch type {
        case .addRules:
            self = .addRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .replaceRules:
            self = .replaceRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .removeRules:
            self = .removeRules(
                destination: destination,
                rules: try container.decode([ClaudePermissionRuleValue].self, forKey: .rules),
                behavior: try container.decode(ClaudePermissionBehavior.self, forKey: .behavior)
            )
        case .setMode:
            self = .setMode(
                destination: destination,
                mode: try container.decode(ClaudePermissionMode.self, forKey: .mode)
            )
        case .addDirectories:
            self = .addDirectories(
                destination: destination,
                directories: try container.decode([String].self, forKey: .directories)
            )
        case .removeDirectories:
            self = .removeDirectories(
                destination: destination,
                directories: try container.decode([String].self, forKey: .directories)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .addRules(destination, rules, behavior):
            try container.encode(UpdateType.addRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .replaceRules(destination, rules, behavior):
            try container.encode(UpdateType.replaceRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .removeRules(destination, rules, behavior):
            try container.encode(UpdateType.removeRules, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(rules, forKey: .rules)
            try container.encode(behavior, forKey: .behavior)
        case let .setMode(destination, mode):
            try container.encode(UpdateType.setMode, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(mode, forKey: .mode)
        case let .addDirectories(destination, directories):
            try container.encode(UpdateType.addDirectories, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(directories, forKey: .directories)
        case let .removeDirectories(destination, directories):
            try container.encode(UpdateType.removeDirectories, forKey: .type)
            try container.encode(destination, forKey: .destination)
            try container.encode(directories, forKey: .directories)
        }
    }

    /// Human-readable label for rendering as a button in the approval card.
    public var displayLabel: String {
        switch self {
        case let .addRules(destination, rules, _):
            guard let rule = rules.first else { return "Yes, always allow" }
            let action = Self.actionVerb(for: rule.toolName)
            let path = Self.shortenedPath(rule.ruleContent)
            let scope = Self.scopeLabel(for: destination)
            if let path {
                return scope.isEmpty
                    ? "Allow \(action) \(path)"
                    : "Allow \(action) \(path) \(scope)"
            }
            return scope.isEmpty
                ? "Always allow \(rule.toolName)"
                : "Always allow \(rule.toolName) \(scope)"
        case let .setMode(_, mode):
            switch mode {
            case .acceptEdits: return "Accept edits mode"
            case .bypassPermissions, .dontAsk: return "Bypass permissions"
            case .plan: return "Plan Mode"
            case .default: return "Manual Mode"
            }
        case .replaceRules: return "Update Rules"
        case .removeRules: return "Remove Rules"
        case .addDirectories: return "Add Directories"
        case .removeDirectories: return "Remove Directories"
        }
    }

    private static func actionVerb(for toolName: String) -> String {
        switch toolName {
        case "Read": return "reading from"
        case "Write", "Edit": return "writing to"
        case "Bash": return "running"
        case "Glob", "Grep": return "searching"
        default: return toolName.lowercased()
        }
    }

    private static func shortenedPath(_ ruleContent: String?) -> String? {
        guard let content = ruleContent, !content.isEmpty else { return nil }
        var path = content
        while path.hasPrefix("/") { path = String(path.dropFirst()) }
        if path.hasSuffix("/**") { path = String(path.dropLast(3)) }
        return path.isEmpty ? nil : path + "/"
    }

    private static func scopeLabel(for destination: ClaudePermissionUpdateDestination) -> String {
        switch destination {
        case .projectSettings: return "from this project"
        case .userSettings: return "globally"
        case .localSettings: return ""
        case .session: return "for this session"
        case .cliArg: return ""
        }
    }
}

// MARK: - Session Start Source

public enum ClaudeSessionStartSource: String, Codable, Sendable {
    case startup
    case resume
    case clear
    case compact
}

// MARK: - Claude Hook Payload (the JSON Claude Code sends to hook stdin)

public struct ClaudeHookPayload: Equatable, Codable, Sendable {
    public var cwd: String
    public var hookEventName: ClaudeHookEventName
    public var sessionID: String
    public var transcriptPath: String?
    public var permissionMode: ClaudePermissionMode?
    public var agentID: String?
    public var agentType: String?
    public var model: String?
    public var source: ClaudeSessionStartSource?
    public var toolName: String?
    public var toolInput: HookJSONValue?
    public var toolUseID: String?
    public var toolResponse: HookJSONValue?
    public var permissionSuggestions: [ClaudePermissionUpdate]?
    public var prompt: String?
    public var message: String?
    public var title: String?
    public var notificationType: String?
    public var stopHookActive: Bool?
    public var lastAssistantMessage: String?
    public var error: String?
    public var errorDetails: String?
    public var isInterrupt: Bool?
    public var agentTranscriptPath: String?
    public var terminalApp: String?
    public var terminalSessionID: String?
    public var terminalTTY: String?
    public var terminalTitle: String?
    public var remote: Bool?

    /// Set by the hooks CLI from the --source argument; not part of the JSON wire format.
    public var hookSource: String?

    private enum CodingKeys: String, CodingKey {
        case cwd
        case hookEventName = "hook_event_name"
        case sessionID = "session_id"
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case agentID = "agent_id"
        case agentType = "agent_type"
        case model
        case source
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseID = "tool_use_id"
        case toolResponse = "tool_response"
        case permissionSuggestions = "permission_suggestions"
        case prompt
        case message
        case title
        case notificationType = "notification_type"
        case stopHookActive = "stop_hook_active"
        case lastAssistantMessage = "last_assistant_message"
        case error
        case errorDetails = "error_details"
        case isInterrupt = "is_interrupt"
        case agentTranscriptPath = "agent_transcript_path"
        case terminalApp = "terminal_app"
        case terminalSessionID = "terminal_session_id"
        case terminalTTY = "terminal_tty"
        case terminalTitle = "terminal_title"
        case remote
    }
}

// MARK: - Permission Request Decision (response sent back to Claude Code)

public enum ClaudePermissionRequestDecision: Equatable, Codable, Sendable {
    case allow(updatedInput: HookJSONValue? = nil, updatedPermissions: [ClaudePermissionUpdate] = [])
    case deny(message: String? = nil, interrupt: Bool = false)

    private enum CodingKeys: String, CodingKey {
        case behavior, updatedInput, updatedPermissions, message, interrupt
    }

    private enum Behavior: String, Codable {
        case allow, deny
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let behavior = try container.decode(Behavior.self, forKey: .behavior)

        switch behavior {
        case .allow:
            self = .allow(
                updatedInput: try container.decodeIfPresent(HookJSONValue.self, forKey: .updatedInput),
                updatedPermissions: try container.decodeIfPresent([ClaudePermissionUpdate].self, forKey: .updatedPermissions) ?? []
            )
        case .deny:
            self = .deny(
                message: try container.decodeIfPresent(String.self, forKey: .message),
                interrupt: try container.decodeIfPresent(Bool.self, forKey: .interrupt) ?? false
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .allow(updatedInput, updatedPermissions):
            try container.encode(Behavior.allow, forKey: .behavior)
            try container.encodeIfPresent(updatedInput, forKey: .updatedInput)
            if !updatedPermissions.isEmpty {
                try container.encode(updatedPermissions, forKey: .updatedPermissions)
            }
        case let .deny(message, interrupt):
            try container.encode(Behavior.deny, forKey: .behavior)
            try container.encodeIfPresent(message, forKey: .message)
            if interrupt {
                try container.encode(true, forKey: .interrupt)
            }
        }
    }
}

// MARK: - PreToolUse Directive

public struct ClaudePreToolUseDirective: Equatable, Codable, Sendable {
    public var permissionDecision: ClaudePermissionBehavior?
    public var permissionDecisionReason: String?
    public var updatedInput: HookJSONValue?
    public var additionalContext: String?

    public init(
        permissionDecision: ClaudePermissionBehavior? = nil,
        permissionDecisionReason: String? = nil,
        updatedInput: HookJSONValue? = nil,
        additionalContext: String? = nil
    ) {
        self.permissionDecision = permissionDecision
        self.permissionDecisionReason = permissionDecisionReason
        self.updatedInput = updatedInput
        self.additionalContext = additionalContext
    }
}

// MARK: - Hook Directive (wrapper for response types)

public enum ClaudeHookDirective: Equatable, Codable, Sendable {
    case preToolUse(ClaudePreToolUseDirective)
    case permissionRequest(ClaudePermissionRequestDecision)

    private enum CodingKeys: String, CodingKey {
        case type, directive
    }

    private enum DirectiveType: String, Codable {
        case preToolUse, permissionRequest
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(DirectiveType.self, forKey: .type)

        switch type {
        case .preToolUse:
            self = .preToolUse(try container.decode(ClaudePreToolUseDirective.self, forKey: .directive))
        case .permissionRequest:
            self = .permissionRequest(try container.decode(ClaudePermissionRequestDecision.self, forKey: .directive))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .preToolUse(directive):
            try container.encode(DirectiveType.preToolUse, forKey: .type)
            try container.encode(directive, forKey: .directive)
        case let .permissionRequest(directive):
            try container.encode(DirectiveType.permissionRequest, forKey: .type)
            try container.encode(directive, forKey: .directive)
        }
    }
}

// MARK: - Hook Output Encoder (formats JSON for Claude Code stdout)

public enum ClaudeHookOutputEncoder {
    private struct PreToolUseOutput: Encodable {
        struct HookSpecificOutput: Encodable {
            var hookEventName = ClaudeHookEventName.preToolUse.rawValue
            var permissionDecision: ClaudePermissionBehavior?
            var permissionDecisionReason: String?
            var updatedInput: HookJSONValue?
            var additionalContext: String?
        }

        var continue_: Bool = true
        var suppressOutput: Bool = true
        var hookSpecificOutput: HookSpecificOutput

        private enum CodingKeys: String, CodingKey {
            case continue_ = "continue"
            case suppressOutput
            case hookSpecificOutput
        }
    }

    private struct PermissionRequestOutput: Encodable {
        struct HookSpecificOutput: Encodable {
            var hookEventName = ClaudeHookEventName.permissionRequest.rawValue
            var decision: ClaudePermissionRequestDecision
        }

        var continue_: Bool = true
        var suppressOutput: Bool = true
        var hookSpecificOutput: HookSpecificOutput

        private enum CodingKeys: String, CodingKey {
            case continue_ = "continue"
            case suppressOutput
            case hookSpecificOutput
        }
    }

    /// Encode a ClaudeHookDirective into the JSON format Claude Code expects on stdout.
    /// Returns nil if no output is needed (e.g., acknowledged responses).
    public static func standardOutput(for directive: ClaudeHookDirective) throws -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data: Data
        switch directive {
        case let .preToolUse(payload):
            data = try encoder.encode(
                PreToolUseOutput(
                    hookSpecificOutput: PreToolUseOutput.HookSpecificOutput(
                        permissionDecision: payload.permissionDecision,
                        permissionDecisionReason: payload.permissionDecisionReason,
                        updatedInput: payload.updatedInput,
                        additionalContext: payload.additionalContext
                    )
                )
            )
        case let .permissionRequest(decision):
            data = try encoder.encode(
                PermissionRequestOutput(
                    hookSpecificOutput: PermissionRequestOutput.HookSpecificOutput(decision: decision)
                )
            )
        }

        var line = data
        line.append(UInt8(ascii: "\n"))
        return line
    }
}

// MARK: - Bridge Command (from bridge CLI -> Island app)

public enum BridgeCommand: Equatable, Codable, Sendable {
    case processClaudeHook(ClaudeHookPayload)

    private enum CodingKeys: String, CodingKey {
        case type, payload
    }

    private enum CommandType: String, Codable {
        case processClaudeHook
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(CommandType.self, forKey: .type)
        switch type {
        case .processClaudeHook:
            self = .processClaudeHook(try container.decode(ClaudeHookPayload.self, forKey: .payload))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .processClaudeHook(payload):
            try container.encode(CommandType.processClaudeHook, forKey: .type)
            try container.encode(payload, forKey: .payload)
        }
    }
}

// MARK: - Bridge Response (from Island app -> bridge CLI)

public enum BridgeResponse: Equatable, Codable, Sendable {
    case acknowledged
    case claudeHookDirective(ClaudeHookDirective)

    private enum CodingKeys: String, CodingKey {
        case type, directive
    }

    private enum ResponseType: String, Codable {
        case acknowledged, claudeHookDirective
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ResponseType.self, forKey: .type)
        switch type {
        case .acknowledged:
            self = .acknowledged
        case .claudeHookDirective:
            self = .claudeHookDirective(try container.decode(ClaudeHookDirective.self, forKey: .directive))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .acknowledged:
            try container.encode(ResponseType.acknowledged, forKey: .type)
        case let .claudeHookDirective(directive):
            try container.encode(ResponseType.claudeHookDirective, forKey: .type)
            try container.encode(directive, forKey: .directive)
        }
    }
}

// MARK: - Bridge Codec

public enum BridgeCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    public static func encodeCommand(_ command: BridgeCommand) throws -> Data {
        var data = try encoder.encode(command)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func encodeResponse(_ response: BridgeResponse) throws -> Data {
        var data = try encoder.encode(response)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    public static func decodeCommand(from data: Data) throws -> BridgeCommand {
        try decoder.decode(BridgeCommand.self, from: data)
    }

    public static func decodeResponse(from data: Data) throws -> BridgeResponse {
        try decoder.decode(BridgeResponse.self, from: data)
    }
}

// MARK: - Convenience extensions on ClaudeHookPayload

public extension ClaudeHookPayload {
    /// Extract a preview of the tool input for display.
    var toolInputPreview: String? {
        guard let input = toolInput else { return nil }
        switch input {
        case let .object(dict):
            // Bash: show command
            if case let .string(cmd)? = dict["command"] { return cmd }
            // Read/Write/Edit: show file_path
            if case let .string(path)? = dict["file_path"] { return path }
            // Grep/Glob: show pattern
            if case let .string(pattern)? = dict["pattern"] { return pattern }
            return nil
        default:
            return nil
        }
    }

    /// Extract file path from tool input.
    var toolInputFilePath: String? {
        toolInput?.stringValue(forKey: "file_path")
    }

    /// Extract command from tool input (for Bash tool).
    var toolInputCommand: String? {
        toolInput?.stringValue(forKey: "command")
    }

    /// Workspace name derived from cwd.
    var workspaceName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }
}
