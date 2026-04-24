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

        // dig starts with a blank line
        if options.showCmd {
            lines.append("")
            // dig omits record type when it's the default (A)
            let typeStr = query.recordType == .A ? "" : " \(query.recordType)"
            lines.append("; <<>> dug \(dugVersion) <<>> \(query.name)\(typeStr)")
            lines.append(";; global options: +cmd")
        }

        // Got answer block (mirrors dig's ->>HEADER<<- + flags lines)
        if options.showComments {
            let status = result.metadata.responseCode
            lines.append(";; Got answer:")
            lines.append(";; ->>RESOLVER<<- query: STANDARD, status: \(status)")
            lines.append(contentsOf: formatFlagsLine(result))
        }

        // System Resolver Pseudosection (analog to dig's OPT PSEUDOSECTION)
        if options.showComments {
            lines.append(contentsOf: formatPseudosection(result.metadata))
        }

        // Question section (dig: ;name.\tIN\tA)
        if options.showQuestion {
            lines.append("")
            lines.append(";; QUESTION SECTION:")
            lines.append(";\(query.name).\t\tIN\t\(query.recordType)")
        }

        // Answer section
        if options.showAnswer, !result.answer.isEmpty {
            lines.append("")
            lines.append(";; ANSWER SECTION:")
            for record in result.answer {
                lines.append(formatRecord(record, options: options))
            }
        }

        // Authority section (SOA for NODATA, or NS from direct DNS)
        if options.showAuthority, !result.authority.isEmpty {
            lines.append("")
            lines.append(";; AUTHORITY SECTION:")
            for record in result.authority {
                lines.append(formatRecord(record, options: options))
            }
        }

        // Resolver section — dug's unique value
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

    private func formatFlagsLine(_ result: ResolutionResult) -> [String] {
        let counts = "QUERY: 1, ANSWER: \(result.answer.count), " +
            "AUTHORITY: \(result.authority.count), ADDITIONAL: \(result.additional.count)"

        // Direct mode: show DNS header flags (qr, rd, ra, etc.)
        if let hflags = result.metadata.headerFlags {
            var names: [String] = []
            if hflags.qr { names.append("qr") }
            if hflags.aa { names.append("aa") }
            if hflags.rd { names.append("rd") }
            if hflags.ra { names.append("ra") }
            if hflags.ad { names.append("ad") }
            if hflags.cd { names.append("cd") }
            return [";; flags: \(names.joined(separator: " ")); \(counts)"]
        }

        // System mode: show resolver behavioral flags (ri, to, etc.)
        if let flags = result.metadata.resolverFlags {
            let flagStr = flags.flagNames.joined(separator: " ")
            return [";; flags: \(flagStr); \(counts)"]
        }

        return [";; \(counts)"]
    }

    /// Analog to dig's OPT PSEUDOSECTION. Only rendered when there is info to show.
    private func formatPseudosection(_ metadata: ResolutionMetadata) -> [String] {
        let hasDnssec = metadata.dnssecStatus != nil
        let hasCache = metadata.answeredFromCache != nil
        guard hasDnssec || hasCache else { return [] }

        var lines = ["", ";; SYSTEM RESOLVER PSEUDOSECTION:"]

        if let dnssec = metadata.dnssecStatus {
            lines.append("; dnssec: \(dnssec.rawValue)")
        }

        if let cached = metadata.answeredFromCache {
            lines.append("; cache: \(cached ? "hit" : "miss")")
        }

        return lines
    }

    private func formatResolverSection(_ metadata: ResolutionMetadata) -> [String] {
        var lines = ["", ";; RESOLVER SECTION:"]

        switch metadata.resolverMode {
        case .system:
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
        case let .direct(server, port):
            lines.append(";; SERVER: \(server)#\(port)")
        }

        lines.append(";; MODE: \(metadata.resolverMode)")
        return lines
    }

    private func formatRecord(_ record: DNSRecord, options: QueryOptions) -> String {
        let ttl = options.humanTTL ? TTLFormatter.humanReadable(record.ttl) : "\(record.ttl)"
        return "\(record.name) \(ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}

extension Duration {
    var milliseconds: Int64 {
        let (seconds, attoseconds) = components
        return seconds * 1000 + attoseconds / 1_000_000_000_000_000
    }
}
