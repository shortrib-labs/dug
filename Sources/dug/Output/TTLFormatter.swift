/// Formats DNS TTL values as human-readable duration strings.
enum TTLFormatter {
    /// Convert a TTL in seconds to a compact human-readable string.
    ///
    /// Uses units: weeks (w), days (d), hours (h), minutes (m), seconds (s).
    /// Zero components are omitted. TTL 0 returns "0s".
    ///
    /// Examples:
    /// - 3661 → "1h1m1s"
    /// - 86400 → "1d"
    /// - 0 → "0s"
    static func humanReadable(_ ttl: UInt32) -> String {
        if ttl == 0 { return "0s" }

        var remaining = ttl
        var parts: [String] = []

        let units: [(UInt32, String)] = [
            (604_800, "w"),
            (86400, "d"),
            (3600, "h"),
            (60, "m"),
            (1, "s")
        ]

        for (divisor, suffix) in units {
            let count = remaining / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                remaining %= divisor
            }
        }

        return parts.joined()
    }
}
