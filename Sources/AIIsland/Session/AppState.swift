import AppKit
import Foundation
import AIIslandProtocol

@Observable
public final class AppState {
    public var sessions: [String: AgentSession] = [:]
    public var currentMode: IslandMode = .idle
    public var pendingPermissions: [PendingPermission] = []
    public var pendingQuestions: [PendingQuestion] = []

    /// Backward-compatible computed properties: return the first queued item.
    public var pendingPermission: PendingPermission? { pendingPermissions.first }
    public var pendingQuestion: PendingQuestion? { pendingQuestions.first }

    /// Sound setting — reads directly from persisted settings so toggle takes effect immediately.
    public var soundEnabled: Bool {
        get { IslandSettings.shared.soundEnabled }
        set { IslandSettings.shared.soundEnabled = newValue }
    }

    /// Tracks socket connections per session for sending responses
    private var sessionConnections: [String: SocketConnection] = [:]

    /// Caches Agent tool descriptions per session as a FIFO queue for subagent tracking.
    /// Multiple Agent calls can be in flight; SubagentStart pops from the front.
    /// NOTE: Claude Code's hook protocol does not include a correlation ID between
    /// PreToolUse(Agent) and SubagentStart, so FIFO ordering is the best-effort
    /// approach. If events arrive out of order, descriptions may be misattributed.
    /// This matches the approach used by open-vibe-island.
    private var pendingAgentDescriptions: [String: [String]] = [:]

    /// Usage data from the statusline cache.
    let usageReader = UsageCacheReader()

    /// Debounce sounds: don't play if last sound was < 2 seconds ago
    private var lastSoundTime: Date = .distantPast

    private let sessionManager = SessionManager()
    private let audio = ChiptuneEngine()

    public init() {
        sessionManager.appState = self
        sessionManager.startExpirationTimer()
        usageReader.startPolling()
    }

    /// Discover existing sessions from transcript files and merge into state.
    func runSessionDiscovery() {
        Task {
            let discovered = await SessionDiscovery.discoverSessions()
            await MainActor.run {
                mergeDiscoveredSessions(discovered)
            }
        }
    }

    /// Merge discovered sessions into the active session map without overwriting live sessions.
    private func mergeDiscoveredSessions(_ discovered: [AgentSession]) {
        var merged = 0
        for session in discovered {
            // Don't overwrite live sessions (those arrived via socket)
            if sessions[session.id] != nil { continue }
            sessions[session.id] = session
            merged += 1
        }
        if merged > 0 {
            NSLog("[AIIsland] Merged \(merged) discovered sessions")
            if currentMode == .idle {
                currentMode = .monitor
            }
        }
    }

    // MARK: - Computed

    /// All sessions sorted by last activity (most recent first)
    public var sortedSessions: [AgentSession] {
        sessions.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    /// Number of active (non-idle, non-done) sessions
    public var activeSessionCount: Int {
        sessions.values.filter {
            $0.status == .working || $0.status == .waitingApproval || $0.status == .waitingAnswer
        }.count
    }

    /// The most recently active session
    public var heroSession: AgentSession? {
        sortedSessions.first { $0.status == .working }
    }

    /// Active task name for the pill
    public var activeTaskName: String {
        if let hero = heroSession {
            return hero.displayName
        }
        if let first = sortedSessions.first {
            return first.displayName
        }
        return "No active tasks"
    }

    // MARK: - Permission Actions

    /// Handle "Allow Once" — no permission updates
    public func handlePermissionResponse(allow: Bool) {
        guard let pending = pendingPermission else { return }

        let decision: ClaudePermissionRequestDecision = allow
            ? .allow()
            : .deny(message: "Denied by AI Island")

        sendPermissionDecision(decision, for: pending.sessionId)

        playDebounced(allow ? .approved : .denied)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingPermissions.removeFirst()
        advanceMode()
    }

    /// Handle a permission response with specific permission updates (e.g., "Always allow Read")
    public func handlePermissionResponse(withUpdates updates: [ClaudePermissionUpdate]) {
        guard let pending = pendingPermission else { return }

        let decision = ClaudePermissionRequestDecision.allow(updatedPermissions: updates)
        sendPermissionDecision(decision, for: pending.sessionId)

        playDebounced(.approved)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingPermissions.removeFirst()
        advanceMode()
    }

    public func handleAskResponse(optionIndex: Int) {
        guard let pending = pendingQuestion else { return }
        // For question responses, we send back as a permission allow with the answer
        // encoded in the updatedInput. For now, just acknowledge.
        sendAcknowledged(for: pending.sessionId)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingQuestions.removeFirst()
        advanceMode()
    }

    public func handleAskResponse(text: String) {
        guard let pending = pendingQuestion else { return }
        sendAcknowledged(for: pending.sessionId)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingQuestions.removeFirst()
        advanceMode()
    }

    public func jumpToSession(_ session: AgentSession) {
        if let pid = session.terminalPid {
            let app = session.terminalApp ?? "Terminal"
            activateTerminal(app: app, pid: pid)
        }
        currentMode = sessions.isEmpty ? .idle : .monitor
    }

    // MARK: - Command Dispatch (from socket server)

    /// Called by SocketServer when a BridgeCommand arrives from the bridge CLI.
    func dispatch(_ command: BridgeCommand, from connection: SocketConnection) {
        switch command {
        case let .processClaudeHook(payload):
            handleClaudeHook(payload, from: connection)
        }
    }

    // MARK: - Claude Hook Processing

    private func handleClaudeHook(_ payload: ClaudeHookPayload, from connection: SocketConnection) {
        let sid = payload.sessionID

        switch payload.hookEventName {
        case .sessionStart:
            let session = AgentSession(
                id: sid,
                agent: .claude,
                prompt: payload.prompt ?? "",
                status: .working,
                startTime: Date(),
                terminalPid: nil,
                terminalApp: payload.terminalApp,
                workingDirectory: payload.cwd ?? "",
                lastActivity: Date(),
                transcriptPath: payload.transcriptPath
            )
            sessions[sid] = session
            sessionConnections[sid] = connection
            currentMode = .monitor
            playDebounced(.sessionStart)
            NSLog("[AIIsland] Session started: \(sid) (\(payload.workspaceName))")
            connection.sendResponse(.acknowledged)

        case .userPromptSubmit:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.status = .working
                session.lastActivity = Date()
                if let prompt = payload.prompt {
                    session.prompt = prompt
                }
            }
            connection.sendResponse(.acknowledged)

        case .preToolUse:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.currentTool = payload.toolName
                session.status = .working
                session.lastActivity = Date()
            }
            // Cache Agent tool description for upcoming SubagentStart (FIFO queue)
            if payload.toolName == "Agent",
               let desc = payload.toolInput?.stringValue(forKey: "description")
                        ?? payload.toolInput?.stringValue(forKey: "prompt")?.prefix(80).description {
                pendingAgentDescriptions[sid, default: []].append(desc)
            }
            connection.sendResponse(.acknowledged)

        case .permissionRequest:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.status = .waitingApproval
                session.lastActivity = Date()
            }

            let toolName = payload.toolName ?? "unknown"
            let command = payload.toolInputCommand
            let filePath = payload.toolInputFilePath
            let suggestions = payload.permissionSuggestions ?? []

            pendingPermissions.append(PendingPermission(
                sessionId: sid,
                toolName: toolName,
                command: command,
                filePath: filePath,
                suggestedUpdates: suggestions,
                toolInput: payload.toolInput,
                toolUseID: payload.toolUseID
            ))
            sessionConnections[sid] = connection
            currentMode = .approve
            playDebounced(.permissionRequest)
            // Do NOT send .acknowledged here — keep the connection open for the decision response

        case .postToolUse:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.currentTool = nil
                session.status = .working
                session.lastActivity = Date()
                // Track TaskCreate/TaskUpdate tool results
                handleTaskToolIfNeeded(session: session, payload: payload)
            }
            connection.sendResponse(.acknowledged)

        case .postToolUseFailure:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.currentTool = nil
                session.status = .error
                session.lastActivity = Date()
            }
            connection.sendResponse(.acknowledged)

        case .notification:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.lastActivity = Date()
            }
            connection.sendResponse(.acknowledged)

        case .stop:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.status = .done
                session.currentTool = nil
                session.lastActivity = Date()
                session.activeSubagents.removeAll()
            }
            playDebounced(.taskComplete)
            // Show jump mode for 5 seconds
            currentMode = .jump
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                guard let self else { return }
                if self.currentMode == .jump {
                    self.currentMode = self.sessions.isEmpty ? .idle : .monitor
                }
            }
            connection.sendResponse(.acknowledged)

        case .stopFailure:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.status = .error
                session.lastActivity = Date()
            }
            playDebounced(.error)
            connection.sendResponse(.acknowledged)

        case .sessionEnd:
            if let session = sessions[sid] {
                session.status = .done
                session.lastActivity = Date()
                session.activeSubagents.removeAll()
            }
            playDebounced(.taskComplete)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.sessions.removeValue(forKey: sid)
                self?.sessionConnections.removeValue(forKey: sid)
                if self?.sessions.isEmpty == true {
                    self?.currentMode = .idle
                } else if self?.currentMode == .jump {
                    self?.currentMode = .monitor
                }
            }
            connection.sendResponse(.acknowledged)
            NSLog("[AIIsland] Session ended: \(sid)")

        case .subagentStart:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.lastActivity = Date()
                if let agentID = payload.agentID {
                    // Pop the oldest queued description (FIFO)
                    var taskDesc: String?
                    if var queue = pendingAgentDescriptions[sid], !queue.isEmpty {
                        taskDesc = queue.removeFirst()
                        pendingAgentDescriptions[sid] = queue.isEmpty ? nil : queue
                    }
                    let info = SubagentInfo(
                        id: agentID,
                        agentType: payload.agentType,
                        taskDescription: taskDesc,
                        startedAt: Date()
                    )
                    session.activeSubagents.append(info)
                    NSLog("[AIIsland] Subagent started: \(agentID) in session \(sid)")
                }
            }
            connection.sendResponse(.acknowledged)

        case .subagentStop:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.lastActivity = Date()
                if let agentID = payload.agentID {
                    session.activeSubagents.removeAll { $0.id == agentID }
                    NSLog("[AIIsland] Subagent stopped: \(agentID) in session \(sid)")
                }
            }
            connection.sendResponse(.acknowledged)

        case .permissionDenied:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.lastActivity = Date()
            }
            connection.sendResponse(.acknowledged)

        case .preCompact:
            ensureSession(id: sid, payload: payload, connection: connection)
            connection.sendResponse(.acknowledged)
        }
    }

    // MARK: - Session Management

    private func ensureSession(id sid: String, payload: ClaudeHookPayload, connection: SocketConnection) {
        if let existing = sessions[sid] {
            if existing.terminalApp == nil, let app = payload.terminalApp {
                existing.terminalApp = app
            }
            if existing.workingDirectory.isEmpty, let cwd = payload.cwd {
                existing.workingDirectory = cwd
            }
            return
        }
        let session = AgentSession(
            id: sid,
            agent: .claude,
            prompt: payload.prompt ?? "",
            status: .working,
            startTime: Date(),
            terminalPid: nil,
            terminalApp: payload.terminalApp,
            workingDirectory: payload.cwd ?? "",
            lastActivity: Date()
        )
        sessions[sid] = session
        sessionConnections[sid] = connection
        if currentMode == .idle {
            currentMode = .monitor
        }
        NSLog("[AIIsland] Session auto-created: \(sid) (\(payload.workspaceName))")
    }

    // MARK: - Response Sending

    private func sendPermissionDecision(_ decision: ClaudePermissionRequestDecision, for sessionId: String) {
        let directive = ClaudeHookDirective.permissionRequest(decision)
        let response = BridgeResponse.claudeHookDirective(directive)
        if let connection = sessionConnections[sessionId] {
            connection.sendResponse(response)
        } else {
            NSLog("[AIIsland] No connection for session \(sessionId)")
        }
    }

    private func sendAcknowledged(for sessionId: String) {
        if let connection = sessionConnections[sessionId] {
            connection.sendResponse(.acknowledged)
        }
    }

    // MARK: - Mode Management

    private func advanceMode() {
        if !pendingPermissions.isEmpty {
            currentMode = .approve
        } else if !pendingQuestions.isEmpty {
            currentMode = .ask
        } else {
            currentMode = sessions.isEmpty ? .idle : .monitor
        }
    }

    // MARK: - Task Tracking

    /// Monotonic counter for generating unique fallback task IDs within a session.
    private var taskSequence: Int = 0

    /// Parse TaskCreate/TaskUpdate tool results and update session task list.
    private func handleTaskToolIfNeeded(session: AgentSession, payload: ClaudeHookPayload) {
        guard let toolName = payload.toolName else { return }

        if toolName == "TaskCreate" {
            guard let input = payload.toolInput else { return }
            let title = input.stringValue(forKey: "subject")
                ?? input.stringValue(forKey: "description")
                ?? "Untitled task"
            // Try to get task ID from the tool response
            let taskID: String
            if case let .object(resp)? = payload.toolResponse,
               case let .string(id)? = resp["taskId"] ?? resp["task_id"] ?? resp["id"] {
                taskID = id
            } else {
                // Unique fallback: sequence number ensures no collision even with identical titles
                taskSequence += 1
                taskID = "_local_\(taskSequence)"
            }
            session.activeTasks.append(TaskInfo(id: taskID, title: title))
        }

        if toolName == "TaskUpdate" {
            guard let input = payload.toolInput else { return }
            let taskID = input.stringValue(forKey: "taskId")
                ?? input.stringValue(forKey: "task_id")
                ?? input.stringValue(forKey: "id")
            guard let taskID else { return }

            if let statusStr = input.stringValue(forKey: "status"),
               let status = TaskInfo.TaskStatus(rawValue: statusStr) {
                // Match by real ID first
                var idx = session.activeTasks.firstIndex(where: { $0.id == taskID })
                // Fallback: match a local-ID task by title for stronger correlation
                if idx == nil {
                    let subject = input.stringValue(forKey: "subject")
                    if let subject, !subject.isEmpty {
                        idx = session.activeTasks.firstIndex(where: {
                            $0.id.hasPrefix("_local_") && $0.title == subject
                        })
                    }
                    // Last resort: oldest unresolved local task (FIFO)
                    if idx == nil {
                        idx = session.activeTasks.firstIndex(where: { $0.id.hasPrefix("_local_") })
                    }
                }
                if let idx {
                    session.activeTasks[idx] = TaskInfo(id: taskID, title: session.activeTasks[idx].title, status: status)
                }
            }
        }
    }

    // MARK: - Private

    /// Play a sound with 2-second debounce to avoid rapid-fire beeping
    private func playDebounced(_ sound: SoundEvent) {
        guard soundEnabled else {
            NSLog("[AIIsland] Sound disabled, skipping")
            return
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(lastSoundTime)
        guard elapsed >= 2.0 else {
            NSLog("[AIIsland] Sound debounced (%.1fs since last)", elapsed)
            return
        }
        lastSoundTime = now
        NSLog("[AIIsland] Playing sound: \(sound)")
        audio.play(sound)
    }

    private func activateTerminal(app: String, pid: Int) {
        Task {
            await TerminalJumper.jump(pid: pid, terminalApp: app)
        }
    }
}
