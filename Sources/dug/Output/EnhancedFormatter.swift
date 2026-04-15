import Foundation

/// dug's enhanced default output format — shows what the system resolver
/// actually provides, including interface name, cache status, and resolver mode.
struct EnhancedFormatter: OutputFormatter {

    static let version = "0.1.0"

    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        var lines: [String] = []

        // Header
        if options.showCmd {
            lines.append("; <<>> dug \(Self.version) <<>> \(query.name) \(query.recordType)")
        }

        // Comments section
        if options.showComments {
            let recordCount = result.records.count
            let msec = result.metadata.queryTime.milliseconds
            lines.append(";; Got answer: \(recordCount) records, query time: \(msec) msec")

            if result.metadata.responseCode != .noError {
                lines.append(";; STATUS: \(result.metadata.responseCode)")
            }

            if let iface = result.metadata.interfaceName {
                lines.append(";; INTERFACE: \(iface)")
            }

            if let cached = result.metadata.answeredFromCache {
                lines.append(";; CACHE: \(cached ? "hit" : "miss")")
            }
        }

        // Answer section
        if options.showAnswer && !result.records.isEmpty {
            if options.showComments {
                lines.append("")  // blank line before records
            }
            for record in result.records {
                lines.append(formatRecord(record))
            }
        }

        // Stats footer
        if options.showStats {
            lines.append("")
            let msec = result.metadata.queryTime.milliseconds
            lines.append(";; Query time: \(msec) msec")

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
            lines.append(";; WHEN: \(dateFormatter.string(from: Date()))")

            lines.append(";; RESOLVER: \(result.metadata.resolverMode)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatRecord(_ record: DNSRecord) -> String {
        let name = record.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        return "\(name)\(record.ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}

// MARK: - Duration helper

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = self.components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
