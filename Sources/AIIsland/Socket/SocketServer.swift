import Foundation
import Network
import AIIslandProtocol

final class SocketServer {

    private let appState: AppState
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: SocketConnection] = [:]
    private let queue = DispatchQueue(label: "com.aiisland.socket-server", qos: .userInitiated)

    init(appState: AppState) {
        self.appState = appState
    }

    // MARK: - Start / Stop

    func start() {
        let socketPath = AIIslandConstants.socketPath
        let socketDir = AIIslandConstants.socketDir
        let fm = FileManager.default

        // Ensure socket directory exists
        if !fm.fileExists(atPath: socketDir) {
            try? fm.createDirectory(atPath: socketDir, withIntermediateDirectories: true)
        }

        // Clean up stale socket file
        if fm.fileExists(atPath: socketPath) {
            try? fm.removeItem(atPath: socketPath)
            NSLog("[AIIsland] Removed stale socket file")
        }

        // Create NWListener on unix domain socket
        let params = NWParameters(tls: nil, tcp: NWProtocolTCP.Options())
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            NSLog("[AIIsland] Failed to create listener: \(error)")
            return
        }

        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                NSLog("[AIIsland] Socket server listening on \(socketPath)")
            case .failed(let error):
                NSLog("[AIIsland] Socket server failed: \(error)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.start()
                }
            case .cancelled:
                NSLog("[AIIsland] Socket server cancelled")
            default:
                break
            }
        }

        listener?.newConnectionHandler = { [weak self] nwConnection in
            self?.handleNewConnection(nwConnection)
        }

        listener?.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for conn in connections.values {
            conn.disconnect()
        }
        connections.removeAll()

        // Clean up socket file
        try? FileManager.default.removeItem(atPath: AIIslandConstants.socketPath)
    }

    // MARK: - Connection Handling

    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = SocketConnection(connection: nwConnection, queue: queue)
        let connId = ObjectIdentifier(connection)

        connection.onCommand = { [weak self] command in
            DispatchQueue.main.async {
                self?.appState.dispatch(command, from: connection)
            }
        }

        connection.onDisconnect = { [weak self] in
            self?.queue.async {
                self?.connections.removeValue(forKey: connId)
                NSLog("[AIIsland] Connection closed. Active: \(self?.connections.count ?? 0)")
            }
        }

        connections[connId] = connection
        connection.start()
        NSLog("[AIIsland] New connection. Active: \(connections.count)")
    }
}
