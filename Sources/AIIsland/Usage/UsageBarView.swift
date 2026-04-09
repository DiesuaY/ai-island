import SwiftUI

/// Compact inline usage display: `C 9%  5H 44%  7D 28%` with color-coded percentages.
struct UsageInlineView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let snapshot = appState.usageReader.latestSnapshot
        if let snapshot, hasUsageData(snapshot) {
            HStack(spacing: 6) {
                if let ctx = snapshot.contextWindow {
                    usageLabel("C", percentage: ctx.usedPercentage)
                }
                if let rl = snapshot.rateLimits {
                    if let fiveHour = rl.fiveHour.usedPercentage {
                        usageLabel("5H", percentage: fiveHour)
                    }
                    if let sevenDay = rl.sevenDay.usedPercentage {
                        usageLabel("7D", percentage: sevenDay)
                    }
                }
            }
        }
    }

    private func usageLabel(_ label: String, percentage: Double) -> some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
            Text("\(Int(percentage))%")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(usageColor(percentage))
        }
    }

    /// Color based on usage level — green/yellow/red.
    private func usageColor(_ percentage: Double) -> Color {
        switch percentage {
        case ..<50: return .green
        case 50..<80: return .yellow
        default: return .red
        }
    }

    private func hasUsageData(_ snapshot: UsageSnapshot) -> Bool {
        snapshot.contextWindow != nil
            || snapshot.rateLimits?.fiveHour.usedPercentage != nil
            || snapshot.rateLimits?.sevenDay.usedPercentage != nil
    }
}
