import SwiftUI

/// Question answering view with clickable option buttons.
struct AskModeView: View {
    @Environment(AppState.self) private var appState
    @State private var textInput: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()
                .overlay(Color.white.opacity(0.1))

            if let pending = appState.pendingQuestion {
                // Question text
                Text(pending.question)
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)

                if pending.options.isEmpty {
                    // Free-form text input when no options provided
                    HStack(spacing: 8) {
                        TextField("Type your answer...", text: $textInput)
                            .textFieldStyle(.plain)
                            .font(DesignTokens.bodyFont)
                            .foregroundStyle(DesignTokens.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
                            .onSubmit {
                                guard !textInput.isEmpty else { return }
                                appState.handleAskResponse(text: textInput)
                            }

                        Button {
                            guard !textInput.isEmpty else { return }
                            appState.handleAskResponse(text: textInput)
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(DesignTokens.accent)
                                .padding(8)
                                .background(DesignTokens.accent.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                } else {
                    // Option buttons
                    VStack(spacing: 6) {
                        ForEach(Array(pending.options.enumerated()), id: \.offset) { index, option in
                            optionButton(index: index, text: option)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(DesignTokens.accent)

            Text("Question")
                .font(DesignTokens.headerFont)
                .foregroundStyle(DesignTokens.textPrimary)

            Spacer()
        }
    }

    // MARK: - Option Button

    private func optionButton(index: Int, text: String) -> some View {
        Button {
            appState.handleAskResponse(optionIndex: index)
        } label: {
            HStack(spacing: 8) {
                // Keyboard shortcut label
                Text("\u{2318}\(index + 1)")
                    .font(DesignTokens.badgeFont)
                    .foregroundStyle(DesignTokens.accent)
                    .frame(width: 28)

                Text(text)
                    .font(DesignTokens.bodyFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(2)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignTokens.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.badgeRadius))
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.badgeRadius)
                    .strokeBorder(DesignTokens.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
