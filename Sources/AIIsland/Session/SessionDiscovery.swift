import Foundation
import AIIslandProtocol

/// Discovers existing Claude Code sessions by scanning transcript files on launch.
/// Parses JSONL files under ~/.claude/projects/ to reconstruct session state.
enum SessionDiscovery {

    /// Maximum age of transcript files to consider (24 hours).
    private static let maxAge: TimeInterval = 24 * 60 * 60

    /// Maximum number of transcript files to parse.
    private static let maxFiles = 40

    /// Discover sessions from transcript files. Runs on a background queue.
    static func discoverSessions() async -> [AgentSession] {
        let projectsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")

        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            NSLog("[AIIsland] No ~/.claude/projects/ directory found")
            return []
        }

        let cutoff = Date().addingTimeInterval(-maxAge)
        let transcriptFiles = findRecentTranscripts(in: projectsDir, after: cutoff)

        NSLog("[AIIsland] Found \(transcriptFiles.count) recent transcript files")

        var sessions: [AgentSession] = []
        for file in transcriptFiles.prefix(maxFiles) {
            if let session = parseTranscript(at: file) {
                sessions.append(session)
            }
        }

        NSLog("[AIIsland] Discovered \(sessions.count) sessions from transcripts")
        return sessions
    }

    // MARK: - File Discovery

    /// Find .jsonl transcript files modified after the cutoff date.
    private static func findRecentTranscripts(in directory: URL, after cutoff: Date) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(url: URL, modDate: Date)] = []

        for case let url as URL in enumerator {
            // Skip subagent transcripts
            if url.path.contains("/subagents/") {
                continue
            }

            guard url.pathExtension == "jsonl" else { continue }

            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let modDate = values.contentModificationDate,
                  modDate > cutoff else { continue }

            files.append((url, modDate))
        }

        // Sort by modification date, most recent first
        files.sort { $0.modDate > $1.modDate }
        return files.map(\.url)
    }

    // MARK: - Transcript Parsing

    /// Parse a single JSONL transcript file to extract session info.
    private static func parseTranscript(at url: URL) -> AgentSession? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var sessionID: String?
        var cwd: String?
        var firstUserPrompt: String?
        var lastUserPrompt: String?
        var earliestTimestamp: Date?
        var latestTimestamp: Date?
        var model: String?
        var currentTool: String?
        var pendingToolUses: Set<String> = [] // tool_use IDs not yet resolved

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let entry = try? decoder.decode(TranscriptEntry.self, from: lineData) else {
                continue
            }

            if let sid = entry.sessionId, sessionID == nil {
                sessionID = sid
            }
            if let dir = entry.cwd, cwd == nil {
                cwd = dir
            }
            if let m = entry.model, model == nil {
                model = m
            }
            if let ts = entry.timestamp {
                if earliestTimestamp == nil || ts < earliestTimestamp! {
                    earliestTimestamp = ts
                }
                if latestTimestamp == nil || ts > latestTimestamp! {
                    latestTimestamp = ts
                }
            }

            // Extract user prompts from message content
            if let msg = entry.message {
                if msg.role == "user" {
                    let text = extractTextContent(msg.content)
                    if !text.isEmpty {
                        if firstUserPrompt == nil { firstUserPrompt = text }
                        lastUserPrompt = text
                    }
                }

                // Track tool use
                if msg.role == "assistant" {
                    for block in msg.contentBlocks {
                        if block.type == "tool_use", let toolName = block.name {
                            pendingToolUses.insert(block.id ?? toolName)
                            currentTool = toolName
                        }
                    }
                }

                // Track tool results
                if msg.role == "user" {
                    for block in msg.contentBlocks {
                        if block.type == "tool_result", let toolUseID = block.toolUseId {
                            pendingToolUses.remove(toolUseID)
                            if pendingToolUses.isEmpty {
                                currentTool = nil
                            }
                        }
                    }
                }
            }
        }

        guard let sessionID else { return nil }

        let prompt = lastUserPrompt ?? firstUserPrompt ?? ""
        let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        // Use earliest timestamp as session start, latest as last activity
        let startDate = earliestTimestamp ?? modDate
        let lastActive = latestTimestamp ?? modDate

        let session = AgentSession(
            id: sessionID,
            agent: .claude,
            prompt: String(prompt.prefix(200)),
            status: .idle,
            currentTool: currentTool,
            startTime: startDate,
            workingDirectory: cwd ?? inferWorkingDirectory(from: url),
            lastActivity: lastActive,
            isDiscovered: true,
            transcriptPath: url.path
        )
        return session
    }

    /// Infer a display-friendly workspace name from the transcript file path.
    /// Paths look like: ~/.claude/projects/-Users-foo-my-project/transcript.jsonl
    /// We only use this as a fallback when cwd is not in the transcript.
    /// Rather than trying to reconstruct the full path (which corrupts hyphenated names),
    /// we just return the raw directory name as a hint.
    private static func inferWorkingDirectory(from url: URL) -> String {
        let dirName = url.deletingLastPathComponent().lastPathComponent
        // Return the raw project key — it's not a valid path but gives context
        return dirName
    }

    /// Extract text content from message content (handles both string and array formats).
    private static func extractTextContent(_ content: TranscriptContent?) -> String {
        guard let content else { return "" }
        switch content {
        case let .text(str):
            return str
        case let .blocks(blocks):
            return blocks.compactMap { block in
                if block.type == "text" { return block.text }
                return nil
            }.joined(separator: " ")
        }
    }
}

// MARK: - Transcript JSON Models

/// Minimal model for a JSONL transcript line.
private struct TranscriptEntry: Decodable {
    var sessionId: String?
    var cwd: String?
    var timestamp: Date?
    var model: String?
    var message: TranscriptMessage?

    enum CodingKeys: String, CodingKey {
        case sessionId, cwd, timestamp, model, message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        message = try container.decodeIfPresent(TranscriptMessage.self, forKey: .message)

        // Parse timestamp flexibly
        if let tsStr = try container.decodeIfPresent(String.self, forKey: .timestamp) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            timestamp = formatter.date(from: tsStr)
            if timestamp == nil {
                formatter.formatOptions = [.withInternetDateTime]
                timestamp = formatter.date(from: tsStr)
            }
        }
    }
}

private struct TranscriptMessage: Decodable {
    var role: String
    var content: TranscriptContent?

    var contentBlocks: [TranscriptContentBlock] {
        guard let content else { return [] }
        switch content {
        case .text:
            return []
        case let .blocks(blocks):
            return blocks
        }
    }
}

private enum TranscriptContent: Decodable {
    case text(String)
    case blocks([TranscriptContentBlock])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            self = .text(text)
        } else if let blocks = try? container.decode([TranscriptContentBlock].self) {
            self = .blocks(blocks)
        } else {
            self = .text("")
        }
    }
}

private struct TranscriptContentBlock: Decodable {
    var type: String
    var text: String?
    var name: String?      // tool name for tool_use
    var id: String?        // tool_use ID
    var toolUseId: String? // for tool_result blocks

    enum CodingKeys: String, CodingKey {
        case type, text, name, id
        case toolUseId = "tool_use_id"
    }
}
