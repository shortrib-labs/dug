import Foundation

/// dug's enhanced default output format — shows what the system resolver
/// actually provides, including interface name, cache status, and resolver mode.
struct EnhancedFormatter: OutputFormatter {
    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return df
    }()

    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        var lines: [String] = []

        if options.showCmd {
            lines.append("; <<>> dug \(dugVersion) <<>> \(query.name) \(query.recordType)")
        }

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

        if options.showAnswer, !result.records.isEmpty {
            if options.showComments {
                lines.append("")
            }
            for record in result.records {
                lines.append(formatRecord(record))
            }
        }

        if options.showStats {
            lines.append("")
            let msec = result.metadata.queryTime.milliseconds
            lines.append(";; Query time: \(msec) msec")
            lines.append(";; WHEN: \(Self.timestampFormatter.string(from: Date()))")
            lines.append(";; RESOLVER: \(result.metadata.resolverMode)")
        }

        return lines.joined(separator: "\n")
    }

    private func formatRecord(_ record: DNSRecord) -> String {
        let name = record.name.padding(toLength: 24, withPad: " ", startingAt: 0)
        return "\(name)\(record.ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
