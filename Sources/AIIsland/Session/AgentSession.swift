import Foundation
import AIIslandProtocol

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
        petSpecies: PetSpecies = .random()
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
