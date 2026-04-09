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
    public var soundEnabled: Bool = true

    /// Tracks socket connections per session for sending responses
    private var sessionConnections: [String: SocketConnection] = [:]

    /// Debounce sounds: don't play if last sound was < 2 seconds ago
    private var lastSoundTime: Date = .distantPast

    private let sessionManager = SessionManager()
    private let audio = ChiptuneEngine()

    public init() {
        sessionManager.appState = self
        sessionManager.startExpirationTimer()
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

    // MARK: - Actions

    public func handlePermissionResponse(allow: Bool) {
        guard let pending = pendingPermission else { return }
        let action: ResponseAction = allow ? .allow : .deny
        let response = AppResponse(sessionId: pending.sessionId, action: action)
        sendResponse(response)

        playDebounced(allow ? .approved : .denied)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingPermissions.removeFirst()
        if !pendingPermissions.isEmpty {
            currentMode = .approve
        } else if !pendingQuestions.isEmpty {
            currentMode = .ask
        } else {
            currentMode = sessions.isEmpty ? .idle : .monitor
        }
    }

    public func handleAskResponse(optionIndex: Int) {
        guard let pending = pendingQuestion else { return }
        let action: ResponseAction = .chooseOption(optionIndex)
        let response = AppResponse(sessionId: pending.sessionId, action: action)
        sendResponse(response)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingQuestions.removeFirst()
        if !pendingQuestions.isEmpty {
            currentMode = .ask
        } else if !pendingPermissions.isEmpty {
            currentMode = .approve
        } else {
            currentMode = sessions.isEmpty ? .idle : .monitor
        }
    }

    public func handleAskResponse(text: String) {
        guard let pending = pendingQuestion else { return }
        let response = AppResponse(
            sessionId: pending.sessionId,
            action: .answer,
            data: ResponseData(text: text)
        )
        sendResponse(response)

        if let session = sessions[pending.sessionId] {
            session.status = .working
        }
        pendingQuestions.removeFirst()
        if !pendingQuestions.isEmpty {
            currentMode = .ask
        } else if !pendingPermissions.isEmpty {
            currentMode = .approve
        } else {
            currentMode = sessions.isEmpty ? .idle : .monitor
        }
    }

    public func jumpToSession(_ session: AgentSession) {
        if let pid = session.terminalPid {
            let app = session.terminalApp ?? "Terminal"
            activateTerminal(app: app, pid: pid)
        }
        currentMode = sessions.isEmpty ? .idle : .monitor
    }

    // MARK: - Message Dispatch (from socket server)

    /// Auto-create a session if one doesn't exist for this session ID.
    private func ensureSession(id sid: String, agent: AgentType, connection: SocketConnection, terminalPid: Int? = nil, terminalApp: String? = nil, workingDirectory: String? = nil) {
        if let existing = sessions[sid] {
            // Update terminal info if we have it and the session doesn't yet
            if existing.terminalPid == nil, let pid = terminalPid {
                existing.terminalPid = pid
            }
            if existing.terminalApp == nil, let app = terminalApp {
                existing.terminalApp = app
            }
            if existing.workingDirectory.isEmpty, let wd = workingDirectory, !wd.isEmpty {
                existing.workingDirectory = wd
            }
            return
        }
        let session = AgentSession(
            id: sid,
            agent: agent,
            prompt: "",
            status: .working,
            startTime: Date(),
            terminalPid: terminalPid,
            terminalApp: terminalApp,
            workingDirectory: workingDirectory ?? "",
            lastActivity: Date()
        )
        sessions[sid] = session
        sessionConnections[sid] = connection
        if currentMode == .idle {
            currentMode = .monitor
        }
        // Don't play sessionStart sound on auto-created sessions from hook events.
        // The explicit .sessionStart event handler plays the sound instead.
        NSLog("[AIIsland] Session auto-created: \(sid) (\(agent.rawValue))")
    }

    /// Called by SocketServer when a message arrives from a bridge connection.
    func dispatch(_ message: BridgeMessage, from connection: SocketConnection) {
        let sid = message.sessionId

        // Auto-create session on first contact (hooks don't send session_start)
        if message.event != .sessionEnd {
            ensureSession(id: sid, agent: message.agent, connection: connection,
                          terminalPid: message.terminalPid, terminalApp: message.terminalApp,
                          workingDirectory: message.workingDirectory)
        }

        switch message.event {
        case .sessionStart:
            guard case .sessionStart(let payload) = message.payload else { return }
            let session = AgentSession(
                id: sid,
                agent: message.agent,
                prompt: payload.prompt ?? "",
                status: .working,
                startTime: message.timestamp,
                terminalPid: payload.terminalPid,
                terminalApp: payload.terminalApp,
                workingDirectory: payload.workingDirectory,
                lastActivity: message.timestamp
            )
            sessions[sid] = session
            sessionConnections[sid] = connection
            currentMode = .monitor
            playDebounced(.sessionStart)
            NSLog("[AIIsland] Session started: \(sid) (\(message.agent.rawValue))")

        case .sessionEnd:
            if case .sessionEnd(let payload) = message.payload {
                if let session = sessions[sid] {
                    session.status = .done
                    session.lastActivity = Date()
                    if let tokens = payload.totalTokens {
                        session.tokenCount = tokens
                    }
                }
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
            NSLog("[AIIsland] Session ended: \(sid)")

        case .toolUse:
            guard case .toolUse(let payload) = message.payload else { return }
            if let session = sessions[sid] {
                session.currentTool = payload.tool
                session.status = .working
                session.lastActivity = Date()
            }

        case .toolResult:
            guard case .toolResult(let payload) = message.payload else { return }
            if let session = sessions[sid] {
                session.currentTool = nil
                session.status = payload.success ? .working : .error
                session.lastActivity = Date()
            }

        case .permissionRequest:
            guard case .permissionRequest(let payload) = message.payload else { return }
            if let session = sessions[sid] {
                session.status = .waitingApproval
                session.lastActivity = Date()
            }
            pendingPermissions.append(PendingPermission(
                sessionId: sid,
                toolName: payload.tool,
                command: payload.command ?? payload.input,
                filePath: payload.filePath,
                diff: payload.diff
            ))
            sessionConnections[sid] = connection
            currentMode = .approve
            playDebounced(.permissionRequest)

        case .ask:
            guard case .ask(let payload) = message.payload else { return }
            if let session = sessions[sid] {
                session.status = .waitingAnswer
                session.lastActivity = Date()
            }
            pendingQuestions.append(PendingQuestion(
                sessionId: sid,
                question: payload.question,
                options: payload.options ?? []
            ))
            sessionConnections[sid] = connection
            currentMode = .ask
            playDebounced(.askPrompt)

        case .thinking:
            if let session = sessions[sid] {
                session.status = .working
                session.currentTool = nil
                session.lastActivity = Date()
            }

        case .response:
            if case .response(let payload) = message.payload {
                if let session = sessions[sid] {
                    if let tokens = payload.tokens {
                        session.tokenCount += tokens
                    }
                    session.status = .done
                    session.currentTool = nil
                    session.lastActivity = Date()
                }
                playDebounced(.taskComplete)
                // Show jump mode for 5 seconds, then return to monitor/idle
                currentMode = .jump
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self = self else { return }
                    if self.currentMode == .jump {
                        self.currentMode = self.sessions.isEmpty ? .idle : .monitor
                    }
                }
            }

        case .error:
            if case .error(let payload) = message.payload {
                if let session = sessions[sid] {
                    session.status = .error
                    session.lastActivity = Date()
                }
                playDebounced(.error)
                NSLog("[AIIsland] Session \(sid) error: \(payload.message)")
            }

        case .heartbeat:
            sessions[sid]?.lastActivity = Date()

        case .permissionResult, .askResponse:
            // Outbound events from bridge side, not expected inbound
            break
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

    private func sendResponse(_ response: AppResponse) {
        if let connection = sessionConnections[response.sessionId] {
            connection.sendResponse(response)
        } else {
            NSLog("[AIIsland] No connection for session \(response.sessionId)")
        }
    }

    private func activateTerminal(app: String, pid: Int) {
        Task {
            await TerminalJumper.jump(pid: pid, terminalApp: app)
        }
    }
}
