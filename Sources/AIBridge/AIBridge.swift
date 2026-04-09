import AIIslandProtocol
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// MARK: - Entry Point

@main
struct AIBridge {
    /// Permission requests get 24 hours — user may respond from the overlay at any time.
    private static let interactiveTimeout: TimeInterval = 24 * 60 * 60
    /// Non-interactive hooks get 45 seconds max.
    private static let defaultTimeout: TimeInterval = 45

    static func main() {
        do {
            // 1. Read stdin (Claude Code pipes JSON here)
            let input = FileHandle.standardInput.readDataToEndOfFile()
            guard !input.isEmpty else { return }

            // 2. Parse --source argument
            let source = parseSource()

            // 3. Decode Claude's native hook payload
            let decoder = JSONDecoder()
            var payload = try decoder.decode(ClaudeHookPayload.self, from: input)
            payload.hookSource = source

            // 4. Determine timeout based on event type
            let timeout = payload.hookEventName == .permissionRequest
                ? interactiveTimeout
                : defaultTimeout

            // 5. Connect to Island app socket and send command
            let socketPath = AIIslandConstants.socketPath
            guard FileManager.default.fileExists(atPath: socketPath) else {
                logStderr("socket not found at \(socketPath)")
                return
            }

            let fd = connectToSocket(path: socketPath)
            guard fd >= 0 else {
                logStderr("could not connect to socket")
                return
            }
            defer { close(fd) }

            // Set socket timeout
            setSocketTimeout(fd: fd, seconds: timeout)

            // 6. Encode and send BridgeCommand
            let command = BridgeCommand.processClaudeHook(payload)
            let wireData = try BridgeCodec.encodeCommand(command)
            guard sendAll(fd: fd, data: wireData) else {
                logStderr("failed to send command")
                return
            }

            // 7. For non-interactive events, we're done after sending
            guard payload.hookEventName == .permissionRequest else {
                // Wait briefly for acknowledgment but don't block
                _ = readResponse(fd: fd, timeoutSeconds: 5)
                return
            }

            // 8. For PermissionRequest: block and wait for the user's decision
            guard let responseData = readResponseLine(fd: fd, timeoutSeconds: Int(interactiveTimeout)) else {
                logStderr("timeout waiting for permission response")
                return
            }

            let response = try BridgeCodec.decodeResponse(from: responseData)

            // 9. Convert BridgeResponse to Claude Code stdout format
            if case let .claudeHookDirective(directive) = response {
                if let output = try ClaudeHookOutputEncoder.standardOutput(for: directive) {
                    FileHandle.standardOutput.write(output)
                }
            }
        } catch {
            // Hooks must fail open — never break the AI agent
            logStderr("hook failed: \(error)")
        }
    }

    // MARK: - Argument Parsing

    private static func parseSource() -> String? {
        let args = CommandLine.arguments
        var i = 1
        while i < args.count {
            if args[i] == "--source", i + 1 < args.count {
                return args[i + 1]
            }
            i += 1
        }
        return nil
    }

    // MARK: - Logging

    private static func logStderr(_ message: String) {
        guard let data = "[aibridge] \(message)\n".data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
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

/// Set send/receive timeouts on a socket.
private func setSocketTimeout(fd: Int32, seconds: TimeInterval) {
    var tv = timeval(
        tv_sec: Int(seconds),
        tv_usec: Int32((seconds - floor(seconds)) * 1_000_000)
    )
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
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

/// Read data from file descriptor until newline (NDJSON line) or timeout.
private func readResponseLine(fd: Int32, timeoutSeconds: Int) -> Data? {
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

        if pollResult < 0 { break }
        if pollResult == 0 { continue }

        let bytesRead = recv(fd, buffer, bufferSize, 0)
        if bytesRead <= 0 { break }

        accumulated.append(buffer, count: bytesRead)

        // NDJSON: look for complete line
        if let newlineIdx = accumulated.firstIndex(of: UInt8(ascii: "\n")) {
            return Data(accumulated[accumulated.startIndex..<newlineIdx])
        }
    }

    return accumulated.isEmpty ? nil : accumulated
}

/// Read any data from socket (used for non-blocking acknowledgment reads).
private func readResponse(fd: Int32, timeoutSeconds: Int) -> Data? {
    var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    let pollResult = poll(&pfd, 1, Int32(timeoutSeconds * 1000))
    guard pollResult > 0 else { return nil }

    let bufferSize = 4096
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
    defer { buffer.deallocate() }

    let bytesRead = recv(fd, buffer, bufferSize, 0)
    guard bytesRead > 0 else { return nil }

    var data = Data()
    data.append(buffer, count: bytesRead)
    return data
}
