import AIIslandProtocol
import Foundation
import os

/// Reads and watches the statusline cache file written by the AI Island statusline script.
/// Polls the file periodically and parses the JSON into a `UsageSnapshot`.
@Observable
final class UsageCacheReader {

    var latestSnapshot: UsageSnapshot?

    private let cachePath: String
    private let logger = Logger(subsystem: "com.aiisland.app", category: "UsageCacheReader")
    private let isoFormatter = ISO8601DateFormatter()
    private var timer: Timer?
    private var lastModified: Date?

    init(cachePath: String = AIIslandConstants.statusCachePath) {
        self.cachePath = cachePath
    }

    deinit {
        timer?.invalidate()
    }

    /// Start polling the cache file.
    func startPolling(interval: TimeInterval = 3.0) {
        stopPolling()
        readCache()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.readCache()
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Private

    private func readCache() {
        let fm = FileManager.default

        guard let attrs = try? fm.attributesOfItem(atPath: cachePath),
              let modified = attrs[.modificationDate] as? Date else { return }

        if let last = lastModified, modified <= last { return }
        lastModified = modified

        guard let data = fm.contents(atPath: cachePath) else { return }

        do {
            let snapshot = try parseStatusJSON(data)
            latestSnapshot = snapshot
        } catch {
            logger.warning("Failed to parse status cache: \(error.localizedDescription)")
        }
    }

    private func parseStatusJSON(_ data: Data) throws -> UsageSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "UsageCacheReader", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"])
        }

        let contextWindow = parseContextWindow(root["context_window"] as? [String: Any])
        let rateLimits = parseRateLimits(root["rate_limits"] as? [String: Any])
        let cost = parseCost(root["cost"] as? [String: Any])
        let modelName = (root["model"] as? [String: Any])?["display_name"] as? String

        return UsageSnapshot(
            contextWindow: contextWindow,
            rateLimits: rateLimits,
            cost: cost,
            modelName: modelName,
            timestamp: Date()
        )
    }

    private func parseContextWindow(_ dict: [String: Any]?) -> ContextWindowUsage? {
        guard let dict else { return nil }
        guard let usedPct = asDouble(dict["used_percentage"]) else { return nil }

        let usage = dict["current_usage"] as? [String: Any]
        return ContextWindowUsage(
            usedPercentage: usedPct,
            contextWindowSize: dict["context_window_size"] as? Int ?? 0,
            inputTokens: usage?["input_tokens"] as? Int ?? 0,
            outputTokens: usage?["output_tokens"] as? Int ?? 0,
            cacheCreationTokens: usage?["cache_creation_input_tokens"] as? Int ?? 0,
            cacheReadTokens: usage?["cache_read_input_tokens"] as? Int ?? 0
        )
    }

    private func parseRateLimits(_ dict: [String: Any]?) -> RateLimits? {
        guard let dict else { return nil }
        return RateLimits(
            fiveHour: parseWindow(dict["five_hour"] as? [String: Any]),
            sevenDay: parseWindow(dict["seven_day"] as? [String: Any])
        )
    }

    private func parseWindow(_ dict: [String: Any]?) -> RateLimitWindow {
        guard let dict else { return RateLimitWindow(usedPercentage: nil, resetsAt: nil) }
        let pct = asDouble(dict["used_percentage"])
        var resets: Date?
        if let timestamp = dict["resets_at"] as? Double {
            resets = Date(timeIntervalSince1970: timestamp)
        } else if let iso = dict["resets_at"] as? String {
            resets = isoFormatter.date(from: iso)
        }
        return RateLimitWindow(usedPercentage: pct, resetsAt: resets)
    }

    private func parseCost(_ dict: [String: Any]?) -> SessionCost? {
        guard let dict else { return nil }
        return SessionCost(
            totalCostUSD: asDouble(dict["total_cost_usd"]) ?? 0,
            totalDurationMs: asDouble(dict["total_duration_ms"]) ?? 0,
            totalLinesAdded: dict["total_lines_added"] as? Int ?? 0,
            totalLinesRemoved: dict["total_lines_removed"] as? Int ?? 0
        )
    }

    private func asDouble(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
