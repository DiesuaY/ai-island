import Foundation
import AIIslandProtocol

/// Info about an active subagent within a session.
public struct SubagentInfo: Identifiable {
    public let id: String           // agentID from the hook payload
    public var agentType: String?   // e.g., "claude-code", "codex"
    public var taskDescription: String?
    public let startedAt: Date

    public init(id: String, agentType: String? = nil, taskDescription: String? = nil, startedAt: Date = Date()) {
        self.id = id
        self.agentType = agentType
        self.taskDescription = taskDescription
        self.startedAt = startedAt
    }
}

/// Info about a tracked task within a session.
public struct TaskInfo: Identifiable {
    public let id: String
    public var title: String
    public var status: TaskStatus

    public enum TaskStatus: String {
        case pending, inProgress = "in_progress", completed
    }

    public init(id: String, title: String, status: TaskStatus = .pending) {
        self.id = id
        self.title = title
        self.status = status
    }
}

@Observable
public final class AgentSession: Identifiable {
    public let id: String
    public var agent: AgentType
    public var prompt: String
    public var status: SessionStatus
    public var currentTool: String?
    public let startTime: Date
    public var terminalPid: Int?
    public var terminalApp: String?
    public var workingDirectory: String
    public var lastActivity: Date
    public var tokenCount: Int
    public var petSpecies: PetSpecies

    /// Active subagents spawned by this session.
    public var activeSubagents: [SubagentInfo] = []

    /// Tracked tasks in this session.
    public var activeTasks: [TaskInfo] = []

    /// Whether this session was discovered from transcript files (vs. live socket).
    public var isDiscovered: Bool = false

    /// Transcript path from the hook payload.
    public var transcriptPath: String?

    public init(
        id: String,
        agent: AgentType = .claude,
        prompt: String = "",
        status: SessionStatus = .idle,
        currentTool: String? = nil,
        startTime: Date = Date(),
        terminalPid: Int? = nil,
        terminalApp: String? = nil,
        workingDirectory: String = "",
        lastActivity: Date = Date(),
        tokenCount: Int = 0,
        petSpecies: PetSpecies = .random(),
        isDiscovered: Bool = false,
        transcriptPath: String? = nil
    ) {
        self.id = id
        self.agent = agent
        self.prompt = prompt
        self.status = status
        self.currentTool = currentTool
        self.startTime = startTime
        self.terminalPid = terminalPid
        self.terminalApp = terminalApp
        self.workingDirectory = workingDirectory
        self.lastActivity = lastActivity
        self.tokenCount = tokenCount
        self.petSpecies = petSpecies
        self.isDiscovered = isDiscovered
        self.transcriptPath = transcriptPath
    }

    /// Display name: first ~40 chars of prompt, or directory basename
    public var displayName: String {
        if !prompt.isEmpty {
            let truncated = prompt.prefix(40)
            return truncated.count < prompt.count ? "\(truncated)..." : String(truncated)
        }
        return URL(fileURLWithPath: workingDirectory).lastPathComponent
    }

    /// Elapsed duration since start
    public var duration: TimeInterval {
        Date().timeIntervalSince(startTime)
    }

    /// Human-readable duration string
    public var durationText: String {
        let elapsed = Int(duration)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
