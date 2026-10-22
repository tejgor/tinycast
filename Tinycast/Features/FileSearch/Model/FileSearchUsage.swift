import Foundation

/// What was opened from Tinycast and when, so a file opened before ranks ahead of its namesakes.
struct FileSearchUsage: Codable, Sendable, Equatable {
    struct Use: Codable, Sendable, Equatable {
        var count: Int
        /// Seconds since the epoch.
        var lastOpened: Double
    }

    static let capacity = 300
    /// Recent use lifts a hit about a tier; an old one still lifts it, by less.
    static let recentBoost = 1_500
    static let staleBoost = 900
    static let repeatBoost = 300
    private static let recentWindow: Double = 30 * 86_400

    private(set) var uses: [String: Use] = [:]

    /// The least recently opened goes first, so a file opened once long ago never crowds one in use.
    func recording(_ path: String, at now: Double) -> FileSearchUsage {
        var next = self
        var use = uses[path] ?? Use(count: 0, lastOpened: now)
        use.count += 1
        use.lastOpened = now
        next.uses[path] = use
        if next.uses.count > Self.capacity {
            let overflow = next.uses.sorted { $0.value.lastOpened < $1.value.lastOpened }
                .prefix(next.uses.count - Self.capacity)
            for (stale, _) in overflow { next.uses[stale] = nil }
        }
        return next
    }

    func removing(_ path: String) -> FileSearchUsage {
        var next = self
        next.uses[path] = nil
        return next
    }

    func boosts(now: Double) -> [String: Int] {
        uses.mapValues { use in
            let base = now - use.lastOpened < Self.recentWindow ? Self.recentBoost : Self.staleBoost
            return base + Self.repeatBoost * (min(use.count, 4) - 1)
        }
    }
}
