import SwiftUI

public enum DesignTokens {
    // MARK: - Colors
    public static let background = Color(red: 0.1, green: 0.1, blue: 0.1)
    public static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)
    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.6)

    // MARK: - Corner Radii
    public static let cardRadius: CGFloat = 12
    public static let badgeRadius: CGFloat = 8
    public static let pillRadius: CGFloat = 16          // Collapsed pill corner radius
    public static let panelRadius: CGFloat = 19

    // MARK: - Sizing
    public static let pillHeight: CGFloat = 32        // Match notch height (~32px on 14" MacBook)
    public static let pillWidth: CGFloat = 156         // Collapsed pill width (fits within visible notch dark area ~160px)
    public static let panelWidth: CGFloat = 380        // Expanded panel width
    public static let approveWidth: CGFloat = 420      // Approve mode width

    // MARK: - Fonts
    public static let codeFont: Font = .system(size: 12, design: .monospaced)
    public static let badgeFont: Font = .system(size: 10, weight: .medium)
    public static let bodyFont: Font = .system(size: 13)
    public static let headerFont: Font = .system(size: 15, weight: .semibold)
}
