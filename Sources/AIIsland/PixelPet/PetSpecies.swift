import SwiftUI

// MARK: - Pixel Pet Species

/// Six adorable 8x8 pixel art creatures for the Dynamic Island.
/// Each species has two animation frames and a base color tint.
public enum PetSpecies: String, CaseIterable, Sendable {
    case cat
    case dog
    case bird
    case octopus
    case robot
    case dragon

    // MARK: - Animation Frames

    /// First animation frame as an 8x8 Bool grid (true = filled pixel).
    public var frame1: [[Bool]] {
        switch self {
        case .cat:
            // Ears up, tail curled
            return Self.parse([
                "..X...X.",
                ".XX..XX.",
                ".X.XX.X.",
                ".X....X.",
                "XXXXXXXX",
                "X.XXXX.X",
                "..X..X..",
                "..X..X..",
            ])
        case .dog:
            // Floppy ears down, tongue out
            return Self.parse([
                "XX....XX",
                "XX.XX.XX",
                "..XXXX..",
                ".XX..XX.",
                ".XXXXXX.",
                "..XXXX..",
                "..X..X..",
                ".X....X.",
            ])
        case .bird:
            // Wings up
            return Self.parse([
                "...XX...",
                "..XXXX..",
                ".XXXXXX.",
                "XX.XX.XX",
                "...XX...",
                "..XXXX..",
                "...XX...",
                "..X..X..",
            ])
        case .octopus:
            // Tentacles spread
            return Self.parse([
                "..XXXX..",
                ".XXXXXX.",
                "X.XXXX.X",
                "X.X..X.X",
                "XXXXXXXX",
                ".XXXXXX.",
                "X.X..X.X",
                "X......X",
            ])
        case .robot:
            // Antenna up, eyes lit
            return Self.parse([
                "...XX...",
                "..XXXX..",
                ".XXXXXX.",
                ".X.XX.X.",
                ".XXXXXX.",
                "..XXXX..",
                ".XX..XX.",
                ".XX..XX.",
            ])
        case .dragon:
            // Wings spread, mouth closed
            return Self.parse([
                ".X..X...",
                ".XX.XXX.",
                "X.XXXX.X",
                "..XXXX..",
                ".XXXXXX.",
                "..XXXX..",
                "..X..X..",
                ".X....X.",
            ])
        }
    }

    /// Second animation frame (subtle movement variation).
    public var frame2: [[Bool]] {
        switch self {
        case .cat:
            // Ears twitch outward
            return Self.parse([
                ".X....X.",
                ".XX..XX.",
                ".X.XX.X.",
                ".X....X.",
                "XXXXXXXX",
                "X.XXXX.X",
                "..X..X..",
                "..X..X..",
            ])
        case .dog:
            // Ears perk up, tongue in
            return Self.parse([
                ".X....X.",
                "XX.XX.XX",
                "..XXXX..",
                ".XX..XX.",
                ".XXXXXX.",
                "..XXXX..",
                ".X....X.",
                "..X..X..",
            ])
        case .bird:
            // Wings down (flap)
            return Self.parse([
                "...XX...",
                "..XXXX..",
                ".XXXXXX.",
                "...XX...",
                "XX.XX.XX",
                "..XXXX..",
                "...XX...",
                "..X..X..",
            ])
        case .octopus:
            // Tentacles wiggle inward
            return Self.parse([
                "..XXXX..",
                ".XXXXXX.",
                "X.XXXX.X",
                "X.X..X.X",
                "XXXXXXXX",
                ".XXXXXX.",
                ".X.XX.X.",
                ".X....X.",
            ])
        case .robot:
            // Antenna blink, eyes toggle
            return Self.parse([
                "...XX...",
                "...XX...",
                ".XXXXXX.",
                ".XX..XX.",
                ".XXXXXX.",
                "..XXXX..",
                ".XX..XX.",
                ".XX..XX.",
            ])
        case .dragon:
            // Wings flap down, mouth open (fire!)
            return Self.parse([
                ".X..X...",
                ".XX.XXX.",
                "..XXXX.X",
                "..XXXX..",
                ".XXXXXX.",
                "X.XXXX.X",
                "..X..X..",
                ".X....X.",
            ])
        }
    }

    // MARK: - Base Color

    /// Default tint color for each species (overridden by status color in practice).
    public var baseColor: Color {
        switch self {
        case .cat:      return .orange
        case .dog:      return .brown
        case .bird:     return .cyan
        case .octopus:  return .purple
        case .robot:    return .gray
        case .dragon:   return .red
        }
    }

    // MARK: - Random

    /// Returns a random pet species.
    public static func random() -> PetSpecies {
        allCases.randomElement() ?? .cat
    }

    // MARK: - Grid Parser

    /// Converts an array of 8-character strings into an 8x8 Bool grid.
    /// `X` = true (filled), `.` = false (empty).
    private static func parse(_ rows: [String]) -> [[Bool]] {
        rows.map { row in
            row.map { $0 == "X" }
        }
    }
}
