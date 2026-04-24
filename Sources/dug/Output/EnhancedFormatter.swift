import Foundation

/// dug's enhanced default output format — mirrors dig's section structure
/// while adding system-resolver-specific metadata that dig can't show.
struct EnhancedFormatter: OutputFormatter {
    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return df
    }()

    func format(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> String {
        var lines: [String] = []
        lines.append(contentsOf: formatCmdHeader(query: query, options: options))
        lines.append(contentsOf: formatGotAnswer(result: result, options: options))
        lines.append(contentsOf: formatQuestionSection(query: query, options: options))
        lines.append(contentsOf: formatAnswerSection(
            result: result, options: options, annotations: annotations
        ))
        lines.append(contentsOf: formatAuthoritySection(result: result, options: options))
        if options.showComments {
            lines.append(contentsOf: formatResolverSection(result.metadata))
        }
        lines.append(contentsOf: formatStatsFooter(result: result, options: options))
        return lines.joined(separator: "\n")
    }

    // MARK: - Top-level sections

    private func formatCmdHeader(query: Query, options: QueryOptions) -> [String] {
        guard options.showCmd else { return [] }
        let typeStr = query.recordType == .A ? "" : " \(query.recordType)"
        return [
            "",
            "; <<>> dug \(dugVersion) <<>> \(query.name)\(typeStr)",
            ";; global options: +cmd"
        ]
    }

    private func formatGotAnswer(result: ResolutionResult, options: QueryOptions) -> [String] {
        guard options.showComments else { return [] }
        var lines: [String] = []
        let status = result.metadata.responseCode
        lines.append(";; Got answer:")
        lines.append(";; ->>RESOLVER<<- query: STANDARD, status: \(status)")
        lines.append(contentsOf: formatFlagsLine(result))
        lines.append(contentsOf: formatPseudosection(result.metadata))
        return lines
    }

    private func formatQuestionSection(query: Query, options: QueryOptions) -> [String] {
        guard options.showQuestion else { return [] }
        return ["", ";; QUESTION SECTION:", ";\(query.name).\t\tIN\t\(query.recordType)"]
    }

    private func formatAnswerSection(
        result: ResolutionResult,
        options: QueryOptions,
        annotations: [String: String]
    ) -> [String] {
        guard options.showAnswer, !result.answer.isEmpty else { return [] }
        var lines = ["", ";; ANSWER SECTION:"]
        for record in result.answer {
            lines.append(formatRecord(record, options: options))
            if let ptrName = annotationForRecord(record, annotations: annotations) {
                lines.append("; -> \(ptrName)")
            }
        }
        return lines
    }

    private func formatAuthoritySection(result: ResolutionResult, options: QueryOptions) -> [String] {
        guard options.showAuthority, !result.authority.isEmpty else { return [] }
        var lines = ["", ";; AUTHORITY SECTION:"]
        for record in result.authority {
            lines.append(formatRecord(record, options: options))
        }
        return lines
    }

    private func formatStatsFooter(result: ResolutionResult, options: QueryOptions) -> [String] {
        guard options.showStats else { return [] }
        let msec = result.metadata.queryTime.milliseconds
        return [
            "",
            ";; Query time: \(msec) msec",
            ";; WHEN: \(Self.timestampFormatter.string(from: Date()))"
        ]
    }

    // MARK: - Detail formatters

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
        let hasEDE = metadata.ednsInfo?.extendedDNSError != nil
        guard hasDnssec || hasCache || hasEDE else { return [] }

        var lines = ["", ";; SYSTEM RESOLVER PSEUDOSECTION:"]

        if let dnssec = metadata.dnssecStatus {
            lines.append("; dnssec: \(dnssec.rawValue)")
        }

        if let cached = metadata.answeredFromCache {
            lines.append("; cache: \(cached ? "hit" : "miss")")
        }

        if let ede = metadata.ednsInfo?.extendedDNSError {
            lines.append(formatEDELine(ede))
        }

        return lines
    }

    private func formatEDELine(_ ede: ExtendedDNSError) -> String {
        let name = ede.infoCodeName ?? "Unknown"
        var line = ";; EDE: \(ede.infoCode) (\(name))"
        if let text = ede.extraText {
            line += ": \"\(text)\""
        }
        return line
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
