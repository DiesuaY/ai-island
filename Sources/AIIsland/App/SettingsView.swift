import SwiftUI

/// Settings window content.
struct SettingsView: View {
    @Bindable var settings: IslandSettings
    @Environment(\.dismiss) private var dismiss

    private let secondsOptions = [5, 10, 15, 20, 30, 60]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text("AI Island Settings")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Sound
                Toggle("Sound Effects", isOn: $settings.soundEnabled)

                Divider()

                // Auto-hide (external monitors only)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Auto-hide on external monitors", isOn: $settings.autoHideEnabled)

                    if settings.autoHideEnabled {
                        HStack {
                            Text("Hide after")
                                .foregroundStyle(.secondary)
                            Picker("", selection: $settings.autoHideSeconds) {
                                ForEach(secondsOptions, id: \.self) { sec in
                                    Text("\(sec)s").tag(sec)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 70)
                            Text("of idle")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("On MacBook screens, the island hides inside the notch area. On external monitors without a notch, enable this to auto-hide the pill after a period of inactivity.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                // Install hooks
                Button("Install / Reinstall Hooks...") {
                    HookInstaller.installAll(force: true)
                }
                .controlSize(.small)

                Text("Installs bridge hooks into Claude Code, Codex, and Gemini CLI config files.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
        }
        .frame(width: 360)
        .fixedSize()
    }
}
