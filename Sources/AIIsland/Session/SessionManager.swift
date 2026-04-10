import Foundation

final class SessionManager {

    /// Auto-expire sessions after this many seconds of no activity
    private let expirationInterval: TimeInterval = 120 // 2 minutes

    private var expirationTimer: Timer?

    weak var appState: AppState?

    // MARK: - Expiration Timer

    func startExpirationTimer() {
        // Check every 60 seconds for stale sessions
        expirationTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.expireStaleSessions()
        }
    }

    func stopExpirationTimer() {
        expirationTimer?.invalidate()
        expirationTimer = nil
    }

    // MARK: - Expiration Logic

    private func expireStaleSessions() {
        guard let appState = appState else { return }
        let now = Date()

        let staleIds = appState.sessions.compactMap { (id, session) -> String? in
            // Don't expire sessions waiting for user input
            guard session.status != .waitingApproval,
                  session.status != .waitingAnswer else { return nil }

            // Discovered sessions use the same 24h window as the transcript scan
            let timeout = session.isDiscovered ? (24 * 60 * 60) : expirationInterval
            let inactive = now.timeIntervalSince(session.lastActivity)
            return inactive > timeout ? id : nil
        }

        for id in staleIds {
            NSLog("[AIIsland] Auto-expiring stale session: \(id)")
            appState.sessions[id]?.status = .done
            appState.sessions.removeValue(forKey: id)
        }

        if appState.sessions.isEmpty && !staleIds.isEmpty {
            appState.currentMode = .idle
        }

        // Also clear sessions stuck in waiting state for too long (bridge timeout is 120s)
        let stuckWaitIds = appState.sessions.compactMap { (id, session) -> String? in
            guard session.status == .waitingApproval || session.status == .waitingAnswer else { return nil }
            let waiting = now.timeIntervalSince(session.lastActivity)
            return waiting > 130 ? id : nil  // 130s > bridge's 120s timeout
        }

        for id in stuckWaitIds {
            NSLog("[AIIsland] Clearing stuck waiting session: \(id)")
            if let session = appState.sessions[id] {
                session.status = .idle
            }
        }

        if !stuckWaitIds.isEmpty {
            // Remove pending items for stuck sessions only
            appState.pendingPermissions.removeAll { pending in
                stuckWaitIds.contains(pending.sessionId)
            }
            appState.pendingQuestions.removeAll { pending in
                stuckWaitIds.contains(pending.sessionId)
            }
            if appState.currentMode == .approve && appState.pendingPermissions.isEmpty {
                appState.currentMode = appState.sessions.isEmpty ? .idle : .monitor
            } else if appState.currentMode == .ask && appState.pendingQuestions.isEmpty {
                appState.currentMode = appState.sessions.isEmpty ? .idle : .monitor
            }
        }
    }

    var activeSessionCount: Int {
        appState?.sessions.values.filter { $0.status != .done }.count ?? 0
    }

    deinit {
        stopExpirationTimer()
    }
}
