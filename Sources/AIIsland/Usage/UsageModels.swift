import Foundation

/// Context window usage data from Claude Code's statusline.
struct ContextWindowUsage: Sendable {
    let usedPercentage: Double
    let contextWindowSize: Int
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
}

/// Rate limit data for a single window (5-hour or 7-day).
struct RateLimitWindow: Sendable {
    let usedPercentage: Double?
    let resetsAt: Date?
}

/// Combined rate limit info from Claude Code's statusline.
struct RateLimits: Sendable {
    let fiveHour: RateLimitWindow
    let sevenDay: RateLimitWindow
}

/// Session cost and stats from Claude Code's statusline.
struct SessionCost: Sendable {
    let totalCostUSD: Double
    let totalDurationMs: Double
    let totalLinesAdded: Int
    let totalLinesRemoved: Int
}

/// Full usage snapshot from the statusline cache.
struct UsageSnapshot: Sendable {
    let contextWindow: ContextWindowUsage?
    let rateLimits: RateLimits?
    let cost: SessionCost?
    let modelName: String?
    let timestamp: Date
}
