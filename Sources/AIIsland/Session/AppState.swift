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
        debugLog("handleAskResponse: optionIndex=\(optionIndex) respondViaKeystroke=\(pending.respondViaKeystroke)")

        if pending.respondViaKeystroke {
            // Send arrow-key navigation to the terminal — the CLI shows a navigable option list
            sendOptionKeystrokeToTerminal(sessionId: pending.sessionId, optionIndex: optionIndex)
        } else {
            let action: ResponseAction = .chooseOption(optionIndex)
            let response = AppResponse(sessionId: pending.sessionId, action: action)
            sendResponse(response)
        }

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

        if pending.respondViaKeystroke {
            sendTextKeystrokeToTerminal(sessionId: pending.sessionId, text: text)
        } else {
            let response = AppResponse(
                sessionId: pending.sessionId,
                action: .answer,
                data: ResponseData(text: text)
            )
            sendResponse(response)
        }

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
                // Track Agent tool nesting — subagent tools fire while Agent is active
                if payload.tool == "Agent" {
                    session.subagentDepth += 1
                    NSLog("[AIIsland] Session \(sid) subagent depth -> \(session.subagentDepth)")
                }
            }

        case .toolResult:
            guard case .toolResult(let payload) = message.payload else { return }
            if let session = sessions[sid] {
                session.currentTool = nil
                session.status = payload.success ? .working : .error
                session.lastActivity = Date()
                // Decrement Agent tool nesting when subagent completes
                if payload.tool == "Agent" {
                    if !payload.success {
                        // Failed Agent call — subagent is dead, reset depth entirely
                        session.subagentDepth = 0
                    } else {
                        session.subagentDepth = max(0, session.subagentDepth - 1)
                    }
                    NSLog("[AIIsland] Session \(sid) subagent depth -> \(session.subagentDepth)")
                }
            }

        case .permissionRequest:
            guard case .permissionRequest(let payload) = message.payload else { return }
            // Auto-approve subagent permission requests — only main agent needs manual approval
            if let session = sessions[sid], session.subagentDepth > 0 {
                NSLog("[AIIsland] Auto-approving subagent permission: \(payload.tool) (depth=\(session.subagentDepth))")
                session.lastActivity = Date()
                let response = AppResponse(sessionId: sid, action: .allow)
                connection.sendResponse(response)
                return
            }
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
            // Ask events from AskUserQuestion tool hooks are fire-and-forget.
            // The island responds by sending a keystroke to the terminal.
            let viaKeystroke = message.terminalPid != nil
            debugLog("ASK received: q=\(payload.question) opts=\(payload.options ?? []) terminalPid=\(String(describing: message.terminalPid)) viaKeystroke=\(viaKeystroke)")
            pendingQuestions.append(PendingQuestion(
                sessionId: sid,
                question: payload.question,
                options: payload.options ?? [],
                respondViaKeystroke: viaKeystroke
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
                    session.subagentDepth = 0  // Reset — any pending subagent calls are dead
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

    private func debugLog(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/aiisland-debug.log"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path) {
                if let fh = FileHandle(forWritingAtPath: path) {
                    fh.seekToEndOfFile(); fh.write(data); fh.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }

    /// Send arrow-key navigation + Enter to select an option in the terminal.
    /// Claude Code's CLI shows a navigable option list — press down-arrow N times then Enter.
    private func sendOptionKeystrokeToTerminal(sessionId: String, optionIndex: Int) {
        guard let session = sessions[sessionId],
              let pid = session.terminalPid else {
            debugLog("No terminal PID for session \(sessionId)")
            return
        }
        let terminalApp = session.terminalApp ?? "Terminal"
        debugLog("sendOptionKeystroke: pid=\(pid) app=\(terminalApp) optionIndex=\(optionIndex)")

        Task { @MainActor in
            let termApp = self.detectTerminalAppName(containingPid: pid)
            self.debugLog("Detected terminal: \(termApp)")

            switch termApp {
            case "iTerm2", "iTerm":
                // Write directly to iTerm2's pty via AppleScript — no focus change needed.
                // Find the correct session by matching tty to the process's controlling terminal.
                await self.sendToITerm2Pty(pid: pid, optionIndex: optionIndex)

            default:
                // Fallback: activate terminal and use CGEvent (requires focus)
                NSApp.keyWindow?.resignKey()
                NSApp.hide(nil)
                let activated = self.activateTerminalApp(containingPid: pid)
                self.debugLog("Fallback CGEvent: activated=\(activated)")
                try? await Task.sleep(nanoseconds: 800_000_000)
                let downArrowKey: CGKeyCode = 125
                let returnKey: CGKeyCode = 36
                for _ in 0..<optionIndex {
                    self.sendKeyEvent(keyCode: downArrowKey)
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
                if optionIndex > 0 {
                    try? await Task.sleep(nanoseconds: 150_000_000)
                }
                self.sendKeyEvent(keyCode: returnKey)
                self.debugLog("CGEvent keystrokes sent")
                try? await Task.sleep(nanoseconds: 500_000_000)
                NSApp.unhide(nil)
            }
        }
    }

    /// Resolve the tty device for a given PID using `ps -o tty=`.
    private func ttyForPid(_ pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-o", "tty=", "-p", "\(pid)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if raw.isEmpty || raw == "??" { return nil }
            // ps returns e.g. "ttys001"; iTerm2 reports "/dev/ttys001"
            return raw.hasPrefix("/dev/") ? raw : "/dev/\(raw)"
        } catch {
            debugLog("ttyForPid error: \(error)")
            return nil
        }
    }

    /// Send down-arrow keystrokes + Enter directly to the iTerm2 session's pty input buffer
    /// by matching the process's tty to the correct iTerm2 session.
    /// This bypasses all focus/CGEvent issues — works even when iTerm2 is not frontmost.
    private func sendToITerm2Pty(pid: Int, optionIndex: Int) async {
        // Resolve which tty the process lives on
        let targetTTY = ttyForPid(pid)
        debugLog("sendToITerm2Pty: pid=\(pid) tty=\(targetTTY ?? "nil") optionIndex=\(optionIndex)")

        // Build down-arrow writes: each is a separate "write text" for reliable delivery
        // Down arrow escape sequence: ESC [B  (character id 27 = ESC)
        var writeStatements = [String]()
        for _ in 0..<optionIndex {
            writeStatements.append("""
                            write text ((character id 27) & "[B") without newline
                            delay 0.05
            """)
        }
        // Enter: CR (character id 13)
        writeStatements.append("""
                            write text (character id 13) without newline
        """)
        let writes = writeStatements.joined(separator: "\n")

        let script: String
        if let tty = targetTTY {
            // Find the exact session by tty — works across multiple windows/tabs
            script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (tty of s) = "\(tty)" then
                                tell s
            \(writes)
                                end tell
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        } else {
            // Fallback: use current session of current window
            debugLog("Could not resolve tty for pid \(pid), using current session")
            script = """
            tell application "iTerm2"
                tell current session of current window
            \(writes)
                end tell
            end tell
            """
        }

        debugLog("AppleScript:\n\(script)")

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            debugLog("AppleScript exit=\(process.terminationStatus) stderr=\(errStr)")
        } catch {
            debugLog("AppleScript error: \(error)")
        }
    }

    /// Detect the terminal app name by walking the process tree.
    private func detectTerminalAppName(containingPid pid: Int) -> String {
        let runningApps = NSWorkspace.shared.runningApplications
        var current = Int32(pid)
        var visited = Set<Int32>()
        while current > 1 && !visited.contains(current) {
            visited.insert(current)
            if let app = runningApps.first(where: { $0.processIdentifier == current && $0.activationPolicy == .regular }) {
                return app.localizedName ?? "Unknown"
            }
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parent = info.kp_eproc.e_ppid
            if parent == current { break }
            current = parent
        }
        return "Unknown"
    }

    /// Activate the terminal app containing the given PID by walking the process tree.
    private func activateTerminalApp(containingPid pid: Int) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        // Walk parent chain to find a terminal app
        var current = Int32(pid)
        var visited = Set<Int32>()
        while current > 1 && !visited.contains(current) {
            visited.insert(current)
            // Check if this PID matches a running app
            if let app = runningApps.first(where: { $0.processIdentifier == current && $0.activationPolicy == .regular }) {
                app.activate(options: .activateIgnoringOtherApps)
                debugLog("Activated app: \(app.localizedName ?? "?") pid=\(current)")
                return true
            }
            // Walk up
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, current]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { break }
            let parent = info.kp_eproc.e_ppid
            if parent == current { break }
            current = parent
        }
        // Fallback: just activate the first terminal-like app
        for app in runningApps where app.activationPolicy == .regular {
            let name = app.localizedName?.lowercased() ?? ""
            if name.contains("terminal") || name.contains("iterm") || name.contains("kitty") ||
               name.contains("ghostty") || name.contains("warp") || name.contains("alacritty") {
                app.activate(options: .activateIgnoringOtherApps)
                debugLog("Fallback activated: \(app.localizedName ?? "?") pid=\(app.processIdentifier)")
                return true
            }
        }
        return false
    }

    /// Send a single key event (down + up) via CGEvent.
    private func sendKeyEvent(keyCode: CGKeyCode) {
        let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false)
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Send text + Enter keystroke to the terminal for free-form answers.
    private func sendTextKeystrokeToTerminal(sessionId: String, text: String) {
        guard let session = sessions[sessionId],
              let pid = session.terminalPid else {
            debugLog("No terminal PID for session \(sessionId)")
            return
        }
        let terminalApp = session.terminalApp ?? "Terminal"
        debugLog("sendTextKeystroke: pid=\(pid) app=\(terminalApp) text=\(text)")

        Task { @MainActor in
            let termApp = self.detectTerminalAppName(containingPid: pid)

            switch termApp {
            case "iTerm2", "iTerm":
                // Write text + newline directly to iTerm2's pty — no focus change needed.
                await self.sendTextToITerm2Pty(pid: pid, text: text)

            default:
                // Fallback: activate terminal and use CGEvent (requires focus)
                await TerminalJumper.jump(pid: pid, terminalApp: terminalApp)
                try? await Task.sleep(nanoseconds: 300_000_000)
                for char in text {
                    var utf16 = Array(String(char).utf16)
                    let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
                    keyDown?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
                    keyDown?.post(tap: .cghidEventTap)
                    let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
                    keyUp?.post(tap: .cghidEventTap)
                }
                self.sendKeyEvent(keyCode: 36)
            }
        }
    }

    /// Send free-form text + Enter directly to the iTerm2 session's pty input buffer.
    private func sendTextToITerm2Pty(pid: Int, text: String) async {
        let targetTTY = ttyForPid(pid)
        debugLog("sendTextToITerm2Pty: pid=\(pid) tty=\(targetTTY ?? "nil") text=\(text)")

        // Escape the text for AppleScript string literal (backslashes and quotes)
        let escapedText = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        // "write text" without "without newline" appends a newline (acts as Enter)
        let writeStmt = "write text \"\(escapedText)\""

        let script: String
        if let tty = targetTTY {
            script = """
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if (tty of s) = "\(tty)" then
                                tell s to \(writeStmt)
                                return
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            """
        } else {
            debugLog("Could not resolve tty for pid \(pid), using current session")
            script = """
            tell application "iTerm2"
                tell current session of current window to \(writeStmt)
            end tell
            """
        }

        debugLog("AppleScript:\n\(script)")

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let stderr = Pipe()
            process.standardError = stderr
            try process.run()
            process.waitUntilExit()
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            debugLog("AppleScript exit=\(process.terminationStatus) stderr=\(errStr)")
        } catch {
            debugLog("AppleScript error: \(error)")
        }
    }
}
