import Foundation

/// dig-style section-based output format. Meaningful with direct DNS
/// which provides authority and additional sections.
struct TraditionalFormatter: OutputFormatter {
    private static let timestampFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE MMM dd HH:mm:ss zzz yyyy"
        return df
    }()

    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        var lines: [String] = []
        lines.append(contentsOf: formatHeader(result: result, query: query, options: options))
        lines.append(contentsOf: formatSections(result: result, query: query, options: options))
        lines.append(contentsOf: formatFooter(result: result, options: options))
        return lines.joined(separator: "\n")
    }

    // MARK: - Header

    private func formatHeader(result: ResolutionResult, query: Query, options: QueryOptions) -> [String] {
        var lines: [String] = []
        if options.showCmd {
            lines.append("")
            let typeStr = query.recordType == .A ? "" : " \(query.recordType)"
            let serverStr = serverPrefix(result.metadata)
            lines.append("; <<>> dug \(dugVersion) <<>> \(serverStr)\(query.name)\(typeStr)")
            lines.append(";; global options: +cmd")
        }
        if options.showComments {
            lines.append(";; Got answer:")
            lines.append(";; ->>HEADER<<- opcode: QUERY, status: \(result.metadata.responseCode)")
            lines.append(formatFlagsLine(result))
        }
        return lines
    }

    // MARK: - Sections

    private func formatSections(result: ResolutionResult, query: Query, options: QueryOptions) -> [String] {
        var lines: [String] = []
        if options.showQuestion {
            lines.append("")
            lines.append(";; QUESTION SECTION:")
            lines.append(";\(query.name).\t\t\(query.recordClass)\t\(query.recordType)")
        }
        lines.append(contentsOf: formatRecordSection(
            ";; ANSWER SECTION:",
            records: result.answer,
            show: options.showAnswer
        ))
        lines.append(contentsOf: formatRecordSection(
            ";; AUTHORITY SECTION:",
            records: result.authority,
            show: options.showAuthority
        ))
        lines.append(contentsOf: formatRecordSection(
            ";; ADDITIONAL SECTION:",
            records: result.additional,
            show: options.showAdditional
        ))
        return lines
    }

    private func formatRecordSection(_ header: String, records: [DNSRecord], show: Bool) -> [String] {
        guard show, !records.isEmpty else { return [] }
        var lines = ["", header]
        for record in records {
            lines.append(formatRecord(record))
        }
        return lines
    }

    // MARK: - Footer

    private func formatFooter(result: ResolutionResult, options: QueryOptions) -> [String] {
        guard options.showStats else { return [] }
        var lines = [""]
        lines.append(";; Query time: \(result.metadata.queryTime.milliseconds) msec")
        if case let .direct(server) = result.metadata.resolverMode {
            lines.append(";; SERVER: \(server)#53")
        }
        lines.append(";; WHEN: \(Self.timestampFormatter.string(from: Date()))")
        return lines
    }

    // MARK: - Helpers

    private func formatFlagsLine(_ result: ResolutionResult) -> String {
        var flagNames: [String] = []
        if let flags = result.metadata.headerFlags {
            if flags.qr { flagNames.append("qr") }
            if flags.aa { flagNames.append("aa") }
            if flags.tc { flagNames.append("tc") }
            if flags.rd { flagNames.append("rd") }
            if flags.ra { flagNames.append("ra") }
            if flags.ad { flagNames.append("ad") }
            if flags.cd { flagNames.append("cd") }
        }
        let flagStr = flagNames.isEmpty ? "" : flagNames.joined(separator: " ")
        let counts = "QUERY: 1, ANSWER: \(result.answer.count), " +
            "AUTHORITY: \(result.authority.count), ADDITIONAL: \(result.additional.count)"
        return ";; flags: \(flagStr); \(counts)"
    }

    private func serverPrefix(_ metadata: ResolutionMetadata) -> String {
        if case let .direct(server) = metadata.resolverMode {
            return "@\(server) "
        }
        return ""
    }

    private func formatRecord(_ record: DNSRecord) -> String {
        "\(record.name) \(record.ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
    }
}
