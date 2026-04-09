import SwiftUI

/// Compact pill shown when the island is idle.
/// Shows a pixel pet placeholder, active task name, and session count badge.
struct IdlePillView: View {
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            // Pixel pet — show hero session's pet or first session's pet
            AnimatedPixelPetView(
                species: (appState.heroSession ?? appState.sortedSessions.first)?.petSpecies ?? .cat,
                status: (appState.heroSession ?? appState.sortedSessions.first)?.status ?? .idle,
                size: 16
            )

            // Active task name, truncated — smaller font for notch
            Text(appState.activeTaskName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(DesignTokens.textPrimary)

            Spacer(minLength: 2)

            // Session count badge — compact
            if appState.sessions.count > 0 {
                sessionBadge
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                appState.currentMode = .monitor
            }
        }
    }

    private var sessionBadge: some View {
        Text("\(appState.sessions.count)")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 16, height: 16)
            .background(DesignTokens.accent)
            .clipShape(Circle())
    }
}
