import SwiftUI

/// Root SwiftUI view that switches between island modes.
struct IslandContentView: View {
    @Environment(AppState.self) private var appState

    /// The notch/safe area height. Content in expanded modes is pushed below this.
    private var notchHeight: CGFloat {
        let screen = ScreenGeometry.activeScreen() ?? NSScreen.main
        return screen?.safeAreaInsets.top ?? 0
    }

    /// Whether the current screen has a notch.
    private var hasNotch: Bool {
        notchHeight > 0
    }

    private var isExpanded: Bool {
        switch appState.currentMode {
        case .idle: return false
        case .monitor, .approve, .ask, .jump: return true
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            DesignTokens.background

            if isExpanded {
                // Expanded modes: content below notch bar (if notch) or with top padding
                VStack(spacing: 0) {
                    if hasNotch {
                        // Notch area: show a mini status bar inside the notch
                        notchBar
                            .frame(height: notchHeight)
                    }

                    // Content area
                    Group {
                        switch appState.currentMode {
                        case .monitor:
                            MonitorModeView()
                                .transition(.move(edge: .top).combined(with: .opacity))
                        case .approve:
                            ApproveModeView()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        case .ask:
                            AskModeView()
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        case .jump:
                            jumpView
                                .transition(.opacity)
                        default:
                            EmptyView()
                        }
                    }
                }
            } else {
                // Collapsed mode: pill sits entirely in the notch
                IdlePillView()
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: appState.currentMode)
        .foregroundStyle(DesignTokens.textPrimary)
    }

    // MARK: - Notch bar (shown in the notch area when expanded)

    /// Title text shown in the notch bar, varies by mode.
    private var notchBarTitle: String {
        switch appState.currentMode {
        case .monitor:
            return "Sessions"
        case .approve:
            if let pending = appState.pendingPermission,
               let session = appState.sessions[pending.sessionId] {
                return session.displayName
            }
            return appState.activeTaskName
        case .ask:
            if let pending = appState.pendingQuestion,
               let session = appState.sessions[pending.sessionId] {
                return session.displayName
            }
            return appState.activeTaskName
        default:
            return appState.activeTaskName
        }
    }

    /// The pet species for the notch bar (from the hero or first session).
    private var notchBarPetSpecies: PetSpecies {
        switch appState.currentMode {
        case .approve:
            if let pending = appState.pendingPermission,
               let session = appState.sessions[pending.sessionId] {
                return session.petSpecies
            }
        case .ask:
            if let pending = appState.pendingQuestion,
               let session = appState.sessions[pending.sessionId] {
                return session.petSpecies
            }
        default:
            break
        }
        if let hero = appState.heroSession {
            return hero.petSpecies
        }
        if let first = appState.sortedSessions.first {
            return first.petSpecies
        }
        return .cat
    }

    /// The pet status for the notch bar.
    private var notchBarPetStatus: SessionStatus {
        switch appState.currentMode {
        case .approve:
            if let pending = appState.pendingPermission,
               let session = appState.sessions[pending.sessionId] {
                return session.status
            }
        case .ask:
            if let pending = appState.pendingQuestion,
               let session = appState.sessions[pending.sessionId] {
                return session.status
            }
        default:
            break
        }
        return appState.heroSession?.status ?? appState.sortedSessions.first?.status ?? .idle
    }

    private var notchBar: some View {
        HStack(spacing: 6) {
            AnimatedPixelPetView(
                species: notchBarPetSpecies,
                status: notchBarPetStatus,
                size: 16
            )

            Text(notchBarTitle)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(DesignTokens.textPrimary)

            Spacer(minLength: 2)

            if appState.currentMode == .monitor, appState.sessions.count > 0 {
                Text("\(appState.sessions.count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(DesignTokens.accent)
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 4)
    }

    // MARK: - Jump mode

    private var jumpView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16))

            Text("Done — click to jump")
                .font(DesignTokens.bodyFont)
                .foregroundStyle(DesignTokens.textPrimary)

            Spacer()

            if let hero = appState.heroSession ?? appState.sortedSessions.first {
                Button {
                    appState.jumpToSession(hero)
                } label: {
                    Text("Open")
                        .font(DesignTokens.badgeFont)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DesignTokens.accent)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: DesignTokens.pillHeight)
    }
}
