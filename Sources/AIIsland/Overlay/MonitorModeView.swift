import SwiftUI
import AIIslandProtocol

/// Expanded view showing all active sessions with a hero card for the most recent.
struct MonitorModeView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovering = true

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            header
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)

            Divider()
                .overlay(Color.white.opacity(0.1))

            if appState.sortedSessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if !hovering {
                // Delay collapse to avoid flicker
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if !isHovering && appState.currentMode == .monitor {
                        appState.currentMode = .idle
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Sessions")
                .font(DesignTokens.headerFont)
                .foregroundStyle(DesignTokens.textPrimary)

            Spacer()

            Text("\(appState.activeSessionCount) active")
                .font(DesignTokens.badgeFont)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        Text("No active sessions")
            .font(DesignTokens.bodyFont)
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 2) {
            // Hero card for most recent active session
            if let hero = appState.heroSession {
                heroCard(for: hero)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
            }

            // All other sessions
            ForEach(appState.sortedSessions.filter { $0.id != appState.heroSession?.id }) { session in
                SessionRowView(session: session)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Hero Card

    private func heroCard(for session: AgentSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Pixel pet
                AnimatedPixelPetView(
                    species: session.petSpecies,
                    status: session.status,
                    size: 24
                )

                Text(session.agent.rawValue.capitalized)
                    .font(DesignTokens.badgeFont)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(agentColor(session.agent).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))

                Spacer()

                // Inline usage indicators
                UsageInlineView()

                statusDot(session.status)

                Text(session.durationText)
                    .font(DesignTokens.badgeFont)
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            // Full prompt
            Text(session.prompt.isEmpty ? session.displayName : session.prompt)
                .font(DesignTokens.bodyFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(3)

            // Current tool activity
            if let tool = session.currentTool {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.textSecondary)
                    Text(tool)
                        .font(DesignTokens.codeFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
        .contentShape(Rectangle())
        .onTapGesture {
            appState.jumpToSession(session)
        }
    }

    // MARK: - Helpers

    private func statusDot(_ status: SessionStatus) -> some View {
        Circle()
            .fill(status.color)
            .frame(width: 8, height: 8)
    }

    private func agentColor(_ agent: AgentType) -> Color {
        switch agent {
        case .claude:   return DesignTokens.accent
        case .codex:    return .green
        case .gemini:   return .blue
        case .cursor:   return .purple
        case .copilot:  return .indigo
        case .aider:    return .mint
        case .opencode: return .cyan
        case .droid:    return .yellow
        case .unknown:  return .gray
        }
    }
}
