import Foundation

// MARK: - Agent Types

public enum AgentType: String, Codable, Sendable {
    case claude = "claude"
    case codex = "codex"
    case copilot = "copilot"
    case cursor = "cursor"
    case aider = "aider"
    case gemini = "gemini"
    case opencode = "opencode"
    case droid = "droid"
    case unknown = "unknown"
}

// MARK: - Agent Events

public enum AgentEvent: String, Codable, Sendable {
    case sessionStart = "session_start"
    case sessionEnd = "session_end"
    case toolUse = "tool_use"
    case toolResult = "tool_result"
    case thinking = "thinking"
    case response = "response"
    case permissionRequest = "permission_request"
    case permissionResult = "permission_result"
    case ask = "ask"
    case askResponse = "ask_response"
    case error = "error"
    case heartbeat = "heartbeat"
}

// MARK: - Bridge Message (from bridge -> island app)

public struct BridgeMessage: Codable, Sendable {
    public let version: Int
    public let sessionId: String
    public let agent: AgentType
    public let event: AgentEvent
    public let timestamp: Date
    public let payload: MessagePayload
    /// Terminal PID passed via --terminal-pid on all hook events.
    public let terminalPid: Int?
    /// Terminal app name passed via --terminal-app on all hook events.
    public let terminalApp: String?
    /// Working directory extracted from Claude Code's stdin JSON (`cwd` field).
    public let workingDirectory: String?

    public init(version: Int = AIIslandConstants.protocolVersion,
                sessionId: String,
                agent: AgentType,
                event: AgentEvent,
                timestamp: Date = Date(),
                payload: MessagePayload,
                terminalPid: Int? = nil,
                terminalApp: String? = nil,
                workingDirectory: String? = nil) {
        self.version = version
        self.sessionId = sessionId
        self.agent = agent
        self.event = event
        self.timestamp = timestamp
        self.payload = payload
        self.terminalPid = terminalPid
        self.terminalApp = terminalApp
        self.workingDirectory = workingDirectory
    }
}

// MARK: - Payload Types

public enum MessagePayload: Codable, Sendable {
    case sessionStart(SessionStartPayload)
    case sessionEnd(SessionEndPayload)
    case toolUse(ToolUsePayload)
    case toolResult(ToolResultPayload)
    case permissionRequest(PermissionRequestPayload)
    case permissionResult(PermissionResultPayload)
    case ask(AskPromptPayload)
    case askResponse(AskResponsePayload)
    case thinking(ThinkingPayload)
    case response(ResponsePayload)
    case error(ErrorPayload)
    case heartbeat(HeartbeatPayload)

    enum CodingKeys: String, CodingKey {
        case type, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "session_start":
            self = .sessionStart(try container.decode(SessionStartPayload.self, forKey: .data))
        case "session_end":
            self = .sessionEnd(try container.decode(SessionEndPayload.self, forKey: .data))
        case "tool_use":
            self = .toolUse(try container.decode(ToolUsePayload.self, forKey: .data))
        case "tool_result":
            self = .toolResult(try container.decode(ToolResultPayload.self, forKey: .data))
        case "permission_request":
            self = .permissionRequest(try container.decode(PermissionRequestPayload.self, forKey: .data))
        case "permission_result":
            self = .permissionResult(try container.decode(PermissionResultPayload.self, forKey: .data))
        case "ask":
            self = .ask(try container.decode(AskPromptPayload.self, forKey: .data))
        case "ask_response":
            self = .askResponse(try container.decode(AskResponsePayload.self, forKey: .data))
        case "thinking":
            self = .thinking(try container.decode(ThinkingPayload.self, forKey: .data))
        case "response":
            self = .response(try container.decode(ResponsePayload.self, forKey: .data))
        case "error":
            self = .error(try container.decode(ErrorPayload.self, forKey: .data))
        case "heartbeat":
            self = .heartbeat(try container.decode(HeartbeatPayload.self, forKey: .data))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                                                    debugDescription: "Unknown payload type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sessionStart(let p):
            try container.encode("session_start", forKey: .type)
            try container.encode(p, forKey: .data)
        case .sessionEnd(let p):
            try container.encode("session_end", forKey: .type)
            try container.encode(p, forKey: .data)
        case .toolUse(let p):
            try container.encode("tool_use", forKey: .type)
            try container.encode(p, forKey: .data)
        case .toolResult(let p):
            try container.encode("tool_result", forKey: .type)
            try container.encode(p, forKey: .data)
        case .permissionRequest(let p):
            try container.encode("permission_request", forKey: .type)
            try container.encode(p, forKey: .data)
        case .permissionResult(let p):
            try container.encode("permission_result", forKey: .type)
            try container.encode(p, forKey: .data)
        case .ask(let p):
            try container.encode("ask", forKey: .type)
            try container.encode(p, forKey: .data)
        case .askResponse(let p):
            try container.encode("ask_response", forKey: .type)
            try container.encode(p, forKey: .data)
        case .thinking(let p):
            try container.encode("thinking", forKey: .type)
            try container.encode(p, forKey: .data)
        case .response(let p):
            try container.encode("response", forKey: .type)
            try container.encode(p, forKey: .data)
        case .error(let p):
            try container.encode("error", forKey: .type)
            try container.encode(p, forKey: .data)
        case .heartbeat(let p):
            try container.encode("heartbeat", forKey: .type)
            try container.encode(p, forKey: .data)
        }
    }
}

public struct SessionStartPayload: Codable, Sendable {
    public let workingDirectory: String
    public let terminalPid: Int?
    public let terminalApp: String?
    public let prompt: String?

    public init(workingDirectory: String, terminalPid: Int? = nil,
                terminalApp: String? = nil, prompt: String? = nil) {
        self.workingDirectory = workingDirectory
        self.terminalPid = terminalPid
        self.terminalApp = terminalApp
        self.prompt = prompt
    }
}

public struct SessionEndPayload: Codable, Sendable {
    public let reason: String?
    public let totalTokens: Int?

    public init(reason: String? = nil, totalTokens: Int? = nil) {
        self.reason = reason
        self.totalTokens = totalTokens
    }
}

public struct ToolUsePayload: Codable, Sendable {
    public let tool: String
    public let input: String?

    public init(tool: String, input: String? = nil) {
        self.tool = tool
        self.input = input
    }
}

public struct ToolResultPayload: Codable, Sendable {
    public let tool: String
    public let success: Bool
    public let output: String?

    public init(tool: String, success: Bool, output: String? = nil) {
        self.tool = tool
        self.success = success
        self.output = output
    }
}

public struct PermissionRequestPayload: Codable, Sendable {
    public let tool: String
    public let input: String?
    public let description: String?
    public let riskLevel: String?
    public let command: String?
    public let filePath: String?
    public let diff: String?

    public init(tool: String, input: String? = nil,
                description: String? = nil, riskLevel: String? = nil,
                command: String? = nil, filePath: String? = nil, diff: String? = nil) {
        self.tool = tool
        self.input = input
        self.description = description
        self.riskLevel = riskLevel
        self.command = command
        self.filePath = filePath
        self.diff = diff
    }
}

public struct PermissionResultPayload: Codable, Sendable {
    public let tool: String
    public let allowed: Bool

    public init(tool: String, allowed: Bool) {
        self.tool = tool
        self.allowed = allowed
    }
}

public struct AskPromptPayload: Codable, Sendable {
    public let question: String
    public let options: [String]?

    public init(question: String, options: [String]? = nil) {
        self.question = question
        self.options = options
    }
}

public struct AskResponsePayload: Codable, Sendable {
    public let answer: String

    public init(answer: String) {
        self.answer = answer
    }
}

public struct ThinkingPayload: Codable, Sendable {
    public let summary: String?

    public init(summary: String? = nil) {
        self.summary = summary
    }
}

public struct ResponsePayload: Codable, Sendable {
    public let text: String?
    public let tokens: Int?

    public init(text: String? = nil, tokens: Int? = nil) {
        self.text = text
        self.tokens = tokens
    }
}

public struct ErrorPayload: Codable, Sendable {
    public let message: String
    public let code: String?

    public init(message: String, code: String? = nil) {
        self.message = message
        self.code = code
    }
}

public struct HeartbeatPayload: Codable, Sendable {
    public let uptimeSeconds: Int?

    public init(uptimeSeconds: Int? = nil) {
        self.uptimeSeconds = uptimeSeconds
    }
}

// MARK: - App Response (from island app -> bridge)

public struct AppResponse: Codable, Sendable {
    public let sessionId: String
    public let action: ResponseAction
    public let data: ResponseData?

    public init(sessionId: String, action: ResponseAction, data: ResponseData? = nil) {
        self.sessionId = sessionId
        self.action = action
        self.data = data
    }
}

public enum ResponseAction: Codable, Sendable, Equatable {
    case allow
    case deny
    case answer
    case dismiss
    case chooseOption(Int)

    enum CodingKeys: String, CodingKey {
        case type, value
    }

    public init(from decoder: Decoder) throws {
        // Try simple string first
        if let container = try? decoder.singleValueContainer(),
           let raw = try? container.decode(String.self) {
            switch raw {
            case "allow": self = .allow
            case "deny": self = .deny
            case "answer": self = .answer
            case "dismiss": self = .dismiss
            default:
                throw DecodingError.dataCorruptedError(in: container,
                    debugDescription: "Unknown action: \(raw)")
            }
            return
        }
        // Try keyed container for chooseOption
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "choose_option":
            let idx = try container.decode(Int.self, forKey: .value)
            self = .chooseOption(idx)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container,
                debugDescription: "Unknown action type: \(type)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .allow:
            var container = encoder.singleValueContainer()
            try container.encode("allow")
        case .deny:
            var container = encoder.singleValueContainer()
            try container.encode("deny")
        case .answer:
            var container = encoder.singleValueContainer()
            try container.encode("answer")
        case .dismiss:
            var container = encoder.singleValueContainer()
            try container.encode("dismiss")
        case .chooseOption(let idx):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("choose_option", forKey: .type)
            try container.encode(idx, forKey: .value)
        }
    }
}

public struct ResponseData: Codable, Sendable {
    public let text: String?

    public init(text: String? = nil) {
        self.text = text
    }
}

// MARK: - Protocol Codec

public enum ProtocolCodec {
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    public static func decode(_ data: Data) throws -> BridgeMessage {
        try decoder.decode(BridgeMessage.self, from: data)
    }

    public static func encode(_ response: AppResponse) throws -> Data {
        try encoder.encode(response)
    }

    public static func encodeLine(_ response: AppResponse) throws -> Data {
        var data = try encode(response)
        data.append(contentsOf: [0x0A]) // newline
        return data
    }
}
