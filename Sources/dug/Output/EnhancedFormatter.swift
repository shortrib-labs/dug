import Foundation

/// dug's enhanced default output format — shows what the system resolver
/// actually provides, including resolver tracing via SystemConfiguration.
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
        }

        // Answer section
        if options.showAnswer, !result.records.isEmpty {
            if options.showComments {
                lines.append("")
            }
            for record in result.records {
                lines.append(formatRecord(record))
            }
        }

        // Resolver section — dug's unique value: trace where the answer came from
        if options.showComments {
            lines.append(contentsOf: formatResolverSection(result.metadata))
        }

        // Stats footer
        if options.showStats {
            lines.append("")
            let msec = result.metadata.queryTime.milliseconds
            lines.append(";; Query time: \(msec) msec")
            lines.append(";; WHEN: \(Self.timestampFormatter.string(from: Date()))")
        }

        return lines.joined(separator: "\n")
    }

    private func formatResolverSection(_ metadata: ResolutionMetadata) -> [String] {
        var lines = ["", ";; RESOLVER SECTION:"]

        if let iface = metadata.interfaceName {
            lines.append(";; INTERFACE: \(iface)")
        }

        if let config = metadata.resolverConfig {
            if !config.nameservers.isEmpty {
                lines.append(";; SERVER: \(config.nameservers.joined(separator: ", "))")
            }
            if !config.searchDomains.isEmpty {
                lines.append(";; SEARCH: \(config.searchDomains.joined(separator: ", "))")
            }
            if let domain = config.domain {
                lines.append(";; DOMAIN: \(domain)")
            }
        }

        if let cached = metadata.answeredFromCache {
            lines.append(";; CACHE: \(cached ? "hit" : "miss")")
        }

        lines.append(";; MODE: \(metadata.resolverMode)")
        return lines
    }

    private func formatRecord(_ record: DNSRecord) -> String {
        "\(record.name)\t\(record.ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
