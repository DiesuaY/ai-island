import SwiftUI
import AIIslandProtocol

/// Single session row showing pet, name, agent badge, duration, and status dot.
struct SessionRowView: View {
    @Environment(AppState.self) private var appState
    let session: AgentSession

    var body: some View {
        HStack(spacing: 8) {
            // Pixel pet
            AnimatedPixelPetView(
                species: session.petSpecies,
                status: session.status,
                size: 16
            )

            // Session name
            Text(session.displayName)
                .font(DesignTokens.bodyFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            // Agent type badge
            Text(session.agent.rawValue.capitalized)
                .font(DesignTokens.badgeFont)
                .foregroundStyle(agentColor(session.agent))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(agentColor(session.agent).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))

            // Subagent count badge
            if !session.activeSubagents.isEmpty {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                    Text("\(session.activeSubagents.count)")
                        .font(DesignTokens.badgeFont)
                }
                .foregroundStyle(.cyan)
            }

            // Task progress badge
            if !session.activeTasks.isEmpty {
                let done = session.activeTasks.filter { $0.status == .completed }.count
                HStack(spacing: 2) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9))
                    Text("\(done)/\(session.activeTasks.count)")
                        .font(DesignTokens.badgeFont)
                }
                .foregroundStyle(DesignTokens.textSecondary)
            }

            // Terminal badge (if has PID)
            if session.terminalPid != nil {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignTokens.textSecondary)
            }

            // Duration
            Text(session.durationText)
                .font(DesignTokens.badgeFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .monospacedDigit()

            // Status dot
            Circle()
                .fill(session.status.color)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.cardRadius))
        .opacity(session.isDiscovered ? 0.7 : 1.0)
        .contentShape(Rectangle())
        .onTapGesture {
            appState.jumpToSession(session)
        }
    }

    // MARK: - Helpers

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
