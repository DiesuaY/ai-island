import Foundation
import Network
import AIIslandProtocol

final class SocketConnection {

    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var didDisconnect = false

    var onMessage: ((BridgeMessage) -> Void)?
    var onDisconnect: (() -> Void)?

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    // MARK: - Lifecycle

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.receiveLoop()
            case .failed:
                self?.fireDisconnect()
            case .cancelled:
                self?.fireDisconnect()
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func disconnect() {
        connection.cancel()
    }

    // MARK: - Receive

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let data = content, !data.isEmpty {
                self.buffer.append(data)
                self.processBuffer()
            }

            if isComplete {
                self.fireDisconnect()
                return
            }

            if let error = error {
                NSLog("[AIIsland] Receive error: \(error)")
                self.fireDisconnect()
                return
            }

            // Continue reading
            self.receiveLoop()
        }
    }

    /// Split buffer on newlines (NDJSON) and decode each complete line
    private func processBuffer() {
        let newline = UInt8(0x0A)

        while let newlineIndex = buffer.firstIndex(of: newline) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[(newlineIndex + 1)...])

            guard !lineData.isEmpty else { continue }

            do {
                let message = try ProtocolCodec.decode(Data(lineData))
                onMessage?(message)
            } catch {
                NSLog("[AIIsland] Failed to decode message: \(error)")
                if let line = String(data: Data(lineData), encoding: .utf8) {
                    NSLog("[AIIsland] Raw line: \(line.prefix(200))")
                }
            }
        }
    }

    private func fireDisconnect() {
        guard !didDisconnect else { return }
        didDisconnect = true
        onDisconnect?()
    }

    // MARK: - Send

    func sendData(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                NSLog("[AIIsland] Send error: \(error)")
            }
        })
    }

    func sendResponse(_ response: AppResponse) {
        do {
            let data = try ProtocolCodec.encodeLine(response)
            sendData(data)
        } catch {
            NSLog("[AIIsland] Failed to encode response: \(error)")
        }
    }
}
