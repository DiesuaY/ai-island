import AIIslandProtocol
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - CLI Argument Parsing

private struct CLIArgs {
    var event: String = ""
    var session: String = ""
    var agent: String = "unknown"
    var terminalPid: Int?
    var terminalApp: String?
}

private func parseArgs() -> CLIArgs {
    var args = CLIArgs()
    let argv = CommandLine.arguments
    var i = 1
    while i < argv.count {
        switch argv[i] {
        case "--event" where i + 1 < argv.count:
            i += 1; args.event = argv[i]
        case "--session" where i + 1 < argv.count:
            i += 1; args.session = argv[i]
        case "--agent" where i + 1 < argv.count:
            i += 1; args.agent = argv[i]
        case "--terminal-pid" where i + 1 < argv.count:
            i += 1; args.terminalPid = Int(argv[i])
        case "--terminal-app" where i + 1 < argv.count:
            i += 1; args.terminalApp = argv[i]
        default:
            break
        }
        i += 1
    }
    return args
}

// MARK: - Stdin Reading

private func readStdinIfAvailable() -> Data? {
    // Check if stdin has data (is not a terminal / has piped input)
    guard !isatty(STDIN_FILENO).toBool() else { return nil }

    var data = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    while true {
        let bytesRead = read(STDIN_FILENO, buffer, bufferSize)
        if bytesRead <= 0 { break }
        data.append(buffer, count: bytesRead)
    }

    return data.isEmpty ? nil : data
}

// MARK: - Event Parsing

private func parseEvent(
    name: String,
    payload: Data?,
    terminalPid: Int?,
    terminalApp: String?
) -> (AgentEvent, MessagePayload)? {
    let json: [String: Any]? = {
        guard let payload else { return nil }
        return try? JSONSerialization.jsonObject(with: payload) as? [String: Any]
    }()

    switch name {
    case "session_start":
        let p = SessionStartPayload(
            workingDirectory: json?["workingDirectory"] as? String ?? "",
            terminalPid: terminalPid,
            terminalApp: terminalApp,
            prompt: json?["prompt"] as? String
        )
        return (.sessionStart, .sessionStart(p))

    case "session_end":
        let p = SessionEndPayload(
            reason: json?["reason"] as? String,
            totalTokens: json?["totalTokens"] as? Int
        )
        return (.sessionEnd, .sessionEnd(p))

    case "tool_use":
        // Claude Code sends: {"tool_name": "Read", "tool_input": {"file_path": "..."}}
        let toolName = json?["tool_name"] as? String ?? json?["toolName"] as? String ?? json?["tool"] as? String ?? "unknown"
        let toolInput = json?["tool_input"] as? [String: Any]
        let inputStr = json?["input"] as? String ?? {
            guard let ti = toolInput else { return nil }
            return (try? JSONSerialization.data(withJSONObject: ti))
                .flatMap { String(data: $0, encoding: .utf8) }
        }()
        let p = ToolUsePayload(tool: toolName, input: inputStr)
        return (.toolUse, .toolUse(p))

    case "tool_result":
        let toolName = json?["tool_name"] as? String ?? json?["toolName"] as? String ?? json?["tool"] as? String ?? "unknown"
        let p = ToolResultPayload(
            tool: toolName,
            success: json?["success"] as? Bool ?? true,
            output: json?["output"] as? String
        )
        return (.toolResult, .toolResult(p))

    case "permission_request":
        let toolName = json?["tool_name"] as? String ?? json?["toolName"] as? String ?? json?["tool"] as? String ?? "unknown"
        let toolInput = json?["tool_input"] as? [String: Any]
        let inputStr = json?["input"] as? String ?? {
            guard let ti = toolInput else { return nil }
            return (try? JSONSerialization.data(withJSONObject: ti))
                .flatMap { String(data: $0, encoding: .utf8) }
        }()
        let p = PermissionRequestPayload(
            tool: toolName,
            input: inputStr,
            description: json?["description"] as? String,
            riskLevel: json?["riskLevel"] as? String,
            command: toolInput?["command"] as? String ?? json?["command"] as? String,
            filePath: toolInput?["file_path"] as? String ?? json?["filePath"] as? String,
            diff: json?["diff"] as? String
        )
        return (.permissionRequest, .permissionRequest(p))

    case "ask":
        var question = json?["question"] as? String ?? ""
        var options = json?["options"] as? [String]

        // Extract from AskUserQuestion tool_input (PreToolUse hook format)
        if question.isEmpty, let toolInput = json?["tool_input"] as? [String: Any] {
            if let questions = toolInput["questions"] as? [[String: Any]], let first = questions.first {
                question = first["question"] as? String ?? ""
                // Options are objects with "label" and "description"
                if let opts = first["options"] as? [[String: Any]] {
                    options = opts.map { opt in
                        opt["label"] as? String ?? opt["description"] as? String ?? "?"
                    }
                }
            }
        }

        let p = AskPromptPayload(
            question: question,
            options: options
        )
        return (.ask, .ask(p))

    case "thinking":
        let p = ThinkingPayload(summary: json?["summary"] as? String)
        return (.thinking, .thinking(p))

    case "response":
        let p = ResponsePayload(
            text: json?["text"] as? String,
            tokens: json?["tokens"] as? Int
        )
        return (.response, .response(p))

    case "status", "notification":
        // Claude Code Notification hook — fires when task completes / waiting for input
        // Map to .response so the app can show completion without killing the session
        let text = json?["message"] as? String ?? json?["title"] as? String ?? "Task complete"
        let p = ResponsePayload(text: text, tokens: nil)
        return (.response, .response(p))

    case "error":
        let message = json?["message"] as? String ?? "unknown error"
        let p = ErrorPayload(message: message, code: json?["code"] as? String)
        return (.error, .error(p))

    case "heartbeat":
        let p = HeartbeatPayload(uptimeSeconds: json?["uptimeSeconds"] as? Int)
        return (.heartbeat, .heartbeat(p))

    default:
        return nil
    }
}

// MARK: - Unix Socket I/O

/// Connect to a Unix domain socket. Returns the file descriptor, or -1 on failure.
private func connectToSocket(path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return -1 }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
        close(fd)
        return -1
    }

    withUnsafeMutablePointer(to: &addr.sun_path) { sunPathPtr in
        sunPathPtr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
            for (i, byte) in pathBytes.enumerated() {
                dest[i] = byte
            }
        }
    }

    let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
    let result = withUnsafePointer(to: &addr) { addrPtr in
        addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
            Darwin.connect(fd, sockaddrPtr, addrLen)
        }
    }

    guard result == 0 else {
        close(fd)
        return -1
    }

    return fd
}

/// Send data over a file descriptor. Returns true on success.
@discardableResult
private func sendAll(fd: Int32, data: Data) -> Bool {
    data.withUnsafeBytes { buffer in
        guard let base = buffer.baseAddress else { return false }
        var sent = 0
        while sent < data.count {
            let n = Darwin.send(fd, base + sent, data.count - sent, 0)
            if n <= 0 { return false }
            sent += n
        }
        return true
    }
}

/// Read data from file descriptor until newline or timeout.
/// Uses poll() for timeout support.
private func readResponse(fd: Int32, timeoutSeconds: Int) -> Data? {
    var accumulated = Data()
    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))

    while Date() < deadline {
        let remainingMs = Int32(deadline.timeIntervalSinceNow * 1000)
        if remainingMs <= 0 { break }

        var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        let pollResult = poll(&pfd, 1, min(remainingMs, 1000))

        if pollResult < 0 { break }  // error
        if pollResult == 0 { continue }  // timeout, loop to check deadline

        let bytesRead = recv(fd, buffer, bufferSize, 0)
        if bytesRead <= 0 { break }

        accumulated.append(buffer, count: bytesRead)

        // NDJSON: check if we have a complete line
        if accumulated.contains(UInt8(ascii: "\n")) {
            return accumulated
        }
    }

    return accumulated.isEmpty ? nil : accumulated
}

// MARK: - Int32 convenience

extension Int32 {
    fileprivate func toBool() -> Bool { self != 0 }
}

// MARK: - Entry Point

@main
struct AIBridge {
    static func main() async throws {
        let cli = parseArgs()

        guard !cli.event.isEmpty, !cli.session.isEmpty else {
            exit(0)  // Missing required args — exit silently
        }

        // Parse the agent type
        let agentType = AgentType(rawValue: cli.agent) ?? .unknown

        // Read stdin payload if piped
        let stdinData = readStdinIfAvailable()

        // Pre-parse stdin JSON to extract session_id and cwd from Claude Code
        var stdinJson: [String: Any]? = nil
        if let data = stdinData {
            stdinJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }

        // Use session_id from stdin JSON if available (Claude Code provides a stable UUID)
        let sessionId: String
        if let claudeSessionId = stdinJson?["session_id"] as? String {
            sessionId = "claude-" + String(claudeSessionId.prefix(8))
        } else {
            sessionId = cli.session
        }

        // Extract cwd from stdin JSON (Claude Code sends it on every hook event)
        let workingDirectory = stdinJson?["cwd"] as? String

        // Subagent detection: Claude Code includes "agent_id" in hook JSON for subagent tool calls.
        // Auto-approve subagent permission requests — only main agent needs manual approval.
        let isSubagent = stdinJson?["agent_id"] != nil

        // Auto-upgrade tool_use to permission_request when Claude Code requires approval.
        // Claude Code sends permission_mode in stdin JSON:
        //   "default" = user must approve dangerous tools
        //   "acceptEdits" = auto-approve edits, ask for Bash
        // For these modes, upgrade to permission_request so the panel shows Allow/Deny.
        // Skip upgrade for subagent calls — they get auto-approved.
        var effectiveEvent = cli.event
        if cli.event == "tool_use" && !isSubagent {
            let toolName = stdinJson?["tool_name"] as? String ?? ""

            // Convert AskUserQuestion to "ask" event so island shows options.
            // This is fire-and-forget — the island responds via terminal keystroke.
            if toolName == "AskUserQuestion" {
                effectiveEvent = "ask"
            } else {
                let permMode = stdinJson?["permission_mode"] as? String ?? ""
                let dangerousTools = ["Bash", "Write", "Edit", "NotebookEdit"]

                if permMode == "default" && dangerousTools.contains(toolName) {
                    effectiveEvent = "permission_request"
                } else if permMode == "acceptEdits" && toolName == "Bash" {
                    effectiveEvent = "permission_request"
                }
            }
        }

        // Parse event
        guard let (event, payload) = parseEvent(
            name: effectiveEvent,
            payload: stdinData,
            terminalPid: cli.terminalPid,
            terminalApp: cli.terminalApp
        ) else {
            exit(0)  // Unknown event — exit silently
        }

        // Construct the BridgeMessage
        let message = BridgeMessage(
            version: AIIslandConstants.protocolVersion,
            sessionId: sessionId,
            agent: agentType,
            event: event,
            timestamp: Date(),
            payload: payload,
            terminalPid: cli.terminalPid,
            terminalApp: cli.terminalApp,
            workingDirectory: workingDirectory
        )

        // Encode to NDJSON
        let jsonEncoder = JSONEncoder()
        jsonEncoder.dateEncodingStrategy = .iso8601
        guard var wireData = try? jsonEncoder.encode(message) else {
            exit(0)
        }
        // Ensure trailing newline for NDJSON
        wireData.append(UInt8(0x0A))

        // Check if socket exists before attempting connection
        let socketPath = AIIslandConstants.socketPath
        guard FileManager.default.fileExists(atPath: socketPath) else {
            exit(0)  // No socket — exit silently
        }

        // Connect to socket
        let fd = connectToSocket(path: socketPath)
        guard fd >= 0 else {
            exit(0)  // Connection failed — exit silently
        }
        defer { close(fd) }

        // Send the message
        guard sendAll(fd: fd, data: wireData) else {
            exit(0)
        }

        // Determine if we need to wait for a response
        // AskUserQuestion "ask" events are fire-and-forget — island responds via terminal keystroke
        let isAskFromTool = effectiveEvent == "ask" && (stdinJson?["tool_name"] as? String) == "AskUserQuestion"
        let needsResponse: Bool = {
            switch effectiveEvent {
            case "permission_request":
                return true
            case "ask":
                return !isAskFromTool  // Only block for native ask events, not tool-intercepted ones
            default:
                return false
            }
        }()

        guard needsResponse else {
            // Fire-and-forget: done
            exit(0)
        }

        // Block and wait for response (120s timeout)
        guard let responseData = readResponse(fd: fd, timeoutSeconds: 120) else {
            // Timeout or read failure
            handleTimeout(event: effectiveEvent)
            exit(1)
        }

        // Decode AppResponse
        // Strip trailing newline for NDJSON
        let trimmedData: Data
        if let newlineIdx = responseData.firstIndex(of: UInt8(0x0A)) {
            trimmedData = Data(responseData[responseData.startIndex..<newlineIdx])
        } else {
            trimmedData = responseData
        }
        let jsonDecoder = JSONDecoder()
        guard let response = try? jsonDecoder.decode(AppResponse.self, from: trimmedData)
        else {
            handleTimeout(event: effectiveEvent)
            exit(1)
        }

        // Handle the response based on event type
        switch effectiveEvent {
        case "permission_request":
            handlePermissionResponse(response.action)

        case "ask":
            handleAskResponse(response)

        default:
            exit(0)
        }
    }

    // MARK: - Response Handlers

    private static func handlePermissionResponse(_ action: ResponseAction) -> Never {
        switch action {
        case .allow:
            print("{\"decision\":\"allow\"}")
            exit(0)
        case .deny:
            print("{\"decision\":\"deny\"}")
            exit(1)
        default:
            print("{\"decision\":\"deny\"}")
            exit(1)
        }
    }

    private static func handleAskResponse(_ response: AppResponse) -> Never {
        switch response.action {
        case .chooseOption(let index):
            print("\(index)")
            exit(0)
        case .answer:
            // Print the free-form text answer to stdout
            let text = response.data?.text ?? ""
            print(text)
            exit(0)
        default:
            exit(1)
        }
    }

    private static func handleTimeout(event: String) {
        if event == "permission_request" {
            print("{\"decision\":\"deny\"}")
        }
    }
}
