import SwiftUI
import AIIslandProtocol

/// Permission approval view with diff preview and rich permission option buttons.
struct ApproveModeView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.1))

            if let pending = appState.pendingPermission {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        // File path
                        if let filePath = pending.filePath {
                            filePathRow(filePath)
                        }

                        // Command
                        if let command = pending.command {
                            commandRow(command)
                        }

                        // Diff view
                        if let diff = pending.diff {
                            diffView(diff)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .frame(maxHeight: 300)
            }

            Divider()
                .overlay(Color.white.opacity(0.1))

            // Action buttons
            actionButtons
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(DesignTokens.accent)

            Text("Permission Request")
                .font(DesignTokens.headerFont)
                .foregroundStyle(DesignTokens.textPrimary)

            if let toolName = appState.pendingPermission?.toolName {
                Text(toolName)
                    .font(DesignTokens.badgeFont)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignTokens.accent.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
                    .foregroundStyle(DesignTokens.accent)
            }

            Spacer()
        }
    }

    // MARK: - File Path

    private func filePathRow(_ path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)

            Text(path)
                .font(DesignTokens.codeFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    // MARK: - Command

    private func commandRow(_ command: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundStyle(DesignTokens.textSecondary)

            Text(command)
                .font(DesignTokens.codeFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Diff View

    private func diffView(_ diff: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            let lines = diff.components(separatedBy: "\n")
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                diffLine(lineNumber: index + 1, content: line)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func diffLine(lineNumber: Int, content: String) -> some View {
        HStack(spacing: 0) {
            Text("\(lineNumber)")
                .font(DesignTokens.codeFont)
                .foregroundStyle(Color.white.opacity(0.3))
                .frame(width: 32, alignment: .trailing)
                .padding(.trailing, 8)

            Text(content)
                .font(DesignTokens.codeFont)
                .foregroundStyle(diffLineColor(content))
                .lineLimit(1)

            Spacer()
        }
        .padding(.vertical, 1)
        .background(diffLineBackground(content))
    }

    private func diffLineColor(_ line: String) -> Color {
        if line.hasPrefix("+") { return Color.green }
        if line.hasPrefix("-") { return Color.red }
        return DesignTokens.textPrimary
    }

    private func diffLineBackground(_ line: String) -> Color {
        if line.hasPrefix("+") { return Color.green.opacity(0.1) }
        if line.hasPrefix("-") { return Color.red.opacity(0.1) }
        return .clear
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 6) {
            // Primary row: Deny + Allow Once
            HStack(spacing: 10) {
                // Deny
                Button {
                    appState.handlePermissionResponse(allow: false)
                } label: {
                    HStack(spacing: 4) {
                        Text("Deny")
                        Text("(\u{2318}N)")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.red.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                Spacer()

                // Allow Once
                Button {
                    appState.handlePermissionResponse(allow: true)
                } label: {
                    HStack(spacing: 4) {
                        Text("Allow Once")
                        Text("(\u{2318}Y)")
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(Color.green.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut("y", modifiers: .command)
            }

            // Permission suggestion buttons (from Claude Code)
            if let pending = appState.pendingPermission, !pending.suggestedUpdates.isEmpty {
                ForEach(Array(pending.suggestedUpdates.enumerated()), id: \.offset) { index, update in
                    Button {
                        appState.handlePermissionResponse(withUpdates: [update])
                    } label: {
                        Text(update.displayLabel)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(suggestionButtonColor(for: update).opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Color for permission suggestion buttons based on the type of update.
    private func suggestionButtonColor(for update: ClaudePermissionUpdate) -> Color {
        switch update {
        case .addRules:
            return DesignTokens.accent
        case .setMode:
            return Color.orange
        default:
            return Color.blue
        }
    }
}
