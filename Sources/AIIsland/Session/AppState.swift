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
                workingDirectory: payload.cwd,
                lastActivity: Date()
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

        case .subagentStart, .subagentStop:
            ensureSession(id: sid, payload: payload, connection: connection)
            if let session = sessions[sid] {
                session.lastActivity = Date()
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
            if existing.workingDirectory.isEmpty {
                existing.workingDirectory = payload.cwd
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
            workingDirectory: payload.cwd,
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
