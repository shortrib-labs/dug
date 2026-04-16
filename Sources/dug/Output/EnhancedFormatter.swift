import Foundation

/// dug's enhanced default output format — mirrors dig's section structure
/// while adding system-resolver-specific metadata that dig can't show.
struct EnhancedFormatter: OutputFormatter {
    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return df
    }()

    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        var lines: [String] = []

        // Header (matches dig: ; <<>> DiG 9.x.x <<>> example.com)
        if options.showCmd {
            lines.append("; <<>> dug \(dugVersion) <<>> \(query.name) \(query.recordType)")
            lines.append(";; global options: +cmd")
        }

        // Got answer block (mirrors dig's HEADER + flags line)
        if options.showComments {
            let answerCount = result.records.count
            let status = result.metadata.responseCode
            lines.append(";; Got answer:")
            lines.append(";; status: \(status), QUERY: 1, ANSWER: \(answerCount), AUTHORITY: 0, ADDITIONAL: 0")
        }

        // System Resolver Pseudosection (our analog to dig's OPT PSEUDOSECTION)
        if options.showComments {
            lines.append(contentsOf: formatPseudosection(result.metadata))
        }

        // Question section (matches dig: ;name.\tCLASS\tTYPE)
        if options.showQuestion {
            lines.append(";; QUESTION SECTION:")
            lines.append(";\(query.name).\t\t\tIN\t\(query.recordType)")
        }

        // Answer section with header
        if options.showAnswer, !result.records.isEmpty {
            lines.append("")
            lines.append(";; ANSWER SECTION:")
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

    // MARK: - Section formatters

    /// Analog to dig's OPT PSEUDOSECTION — shows system resolver metadata.
    /// Only rendered when there is DNSSEC or cache info to show.
    private func formatPseudosection(_ metadata: ResolutionMetadata) -> [String] {
        let hasDnssec = metadata.dnssecStatus != nil
        let hasCache = metadata.answeredFromCache != nil
        guard hasDnssec || hasCache else { return [] }

        var lines = [";; SYSTEM RESOLVER PSEUDOSECTION:"]

        if let dnssec = metadata.dnssecStatus {
            lines.append("; DNSSEC: \(dnssec.rawValue)")
        }

        if let cached = metadata.answeredFromCache {
            lines.append("; cache: \(cached ? "hit" : "miss")")
        }

        return lines
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

        lines.append(";; MODE: \(metadata.resolverMode)")
        return lines
    }

    /// Format a record like dig: name. TTL\tCLASS\tTYPE\trdata
    /// Note the space (not tab) between name and TTL — this is how dig does it.
    private func formatRecord(_ record: DNSRecord) -> String {
        "\(record.name) \(record.ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
