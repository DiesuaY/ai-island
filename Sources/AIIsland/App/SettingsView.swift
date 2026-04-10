import SwiftUI

/// Settings window content.
struct SettingsView: View {
    @Bindable var settings: IslandSettings
    @Environment(\.dismiss) private var dismiss

    @State private var healthReports: [HookHealthReport] = []
    @State private var isRunningHealthCheck = false
    @State private var repairResult: (message: String, succeeded: Bool)?

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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: - General
                    sectionHeader("General")

                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)

                    Toggle("Show Dock Icon", isOn: $settings.showDockIcon)

                    Text("When disabled, AI Island runs as a menu bar app only.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Divider()

                    // MARK: - Appearance
                    sectionHeader("Appearance")

                    Toggle("Sound Effects", isOn: $settings.soundEnabled)

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

                    // MARK: - Hooks
                    sectionHeader("Hooks")

                    Button("Install / Reinstall Hooks...") {
                        HookInstaller.installAll(mode: .bootstrap)
                    }
                    .controlSize(.small)

                    Text("Installs bridge hooks into Claude Code, Codex, and Gemini CLI config files.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    Divider()

                    // MARK: - Diagnostics
                    sectionHeader("Diagnostics")

                    HStack {
                        Button(isRunningHealthCheck ? "Checking..." : "Run Health Check") {
                            runHealthCheck()
                        }
                        .controlSize(.small)
                        .disabled(isRunningHealthCheck)

                        if !healthReports.isEmpty {
                            let hasRepairable = healthReports.contains { !$0.repairableIssues.isEmpty }
                            if hasRepairable {
                                Button("Repair") {
                                    repairHooks()
                                }
                                .controlSize(.small)
                            }
                        }
                    }

                    if let result = repairResult {
                        Text(result.message)
                            .font(.caption)
                            .foregroundStyle(result.succeeded ? .green : .orange)
                    }

                    if !healthReports.isEmpty {
                        ForEach(healthReports, id: \.agent) { report in
                            hookHealthRow(report)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 400, height: 520)
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func hookHealthRow(_ report: HookHealthReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: report.isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(report.isHealthy ? .green : .orange)
                    .font(.system(size: 12))
                Text(report.agent.capitalized)
                    .font(.caption.weight(.medium))
                if report.isHealthy {
                    Text("Healthy")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            ForEach(Array(report.issues.enumerated()), id: \.offset) { _, issue in
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: issueIcon(issue))
                        .foregroundStyle(issueColor(issue))
                        .font(.system(size: 10))
                    Text(issue.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 20)
            }
        }
    }

    private func issueIcon(_ issue: HookHealthReport.Issue) -> String {
        switch issue.severity {
        case .error:
            issue.isAutoRepairable ? "wrench.fill" : "xmark.circle.fill"
        case .info:
            "info.circle.fill"
        }
    }

    private func issueColor(_ issue: HookHealthReport.Issue) -> Color {
        switch issue.severity {
        case .error: .orange
        case .info: .blue
        }
    }

    // MARK: - Actions

    private func runHealthCheck(clearRepairResult: Bool = true) {
        isRunningHealthCheck = true
        if clearRepairResult { repairResult = nil }
        DispatchQueue.global(qos: .userInitiated).async {
            let reports = HookHealthCheck.checkAll()
            DispatchQueue.main.async {
                healthReports = reports
                isRunningHealthCheck = false
            }
        }
    }

    private func repairHooks() {
        let succeeded = HookInstaller.installAll(mode: .forceReinstall)
        repairResult = (
            message: succeeded ? "Hooks repaired successfully." : "Some hooks failed to install. Check logs for details.",
            succeeded: succeeded
        )
        runHealthCheck(clearRepairResult: false)
    }
}
