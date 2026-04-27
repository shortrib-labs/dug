import Foundation
import Yams

/// Produces YAML output for DNS results.
///
/// Content mode behavior:
/// - Default (enhanced): full object with query, answer, authority, additional, metadata
/// - `+short`: YAML sequence of rdata strings
/// - Section toggles apply: `+noall +answer` produces only the answer key
struct YamlFormatter: StructuredOutputFormatter {
    func format(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> String {
        if options.shortOutput {
            return formatShort(result: result)
        }
        let response = buildResponse(result: result, query: query, options: options, annotations: annotations)
        return encodeYAML([response])
    }

    /// Format a single result as a `StructuredResponse`, respecting section toggles.
    func buildResponse(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> StructuredResponse {
        let showQuery = options.showCmd || options.showQuestion
        let showStats = options.showStats || options.showComments

        return StructuredResponse(
            query: showQuery ? buildQuery(query) : nil,
            answer: options.showAnswer
                ? buildRecords(result.answer, options: options, annotations: annotations) : nil,
            authority: options.showAuthority
                ? buildRecords(result.authority, options: options, annotations: [:]) : nil,
            additional: options.showAdditional
                ? buildRecords(result.additional, options: options, annotations: [:]) : nil,
            metadata: showStats ? buildMetadata(result.metadata) : nil
        )
    }

    /// Encode a short-mode result: flat sequence of rdata strings.
    func formatShort(result: ResolutionResult) -> String {
        let values = result.answer.map(\.rdata.shortDescription)
        return encodeYAML(values)
    }

    /// Encode an error result for a failed type in multi-type queries.
    func formatError(query: Query, error: DugError) -> StructuredErrorResult {
        StructuredErrorResult(
            query: buildQuery(query),
            error: StructuredError(
                code: error.exitCode,
                message: error.description
            )
        )
    }

    // MARK: - Builders

    private func buildQuery(_ query: Query) -> StructuredQuery {
        StructuredQuery(
            name: query.name,
            type: query.recordType.description,
            class: query.recordClass.description
        )
    }

    private func buildRecords(
        _ records: [DNSRecord],
        options: QueryOptions,
        annotations: [String: String]
    ) -> [StructuredRecord] {
        records.map { record in
            let ptrAnnotation = annotationForRecord(record, annotations: annotations)
            return StructuredRecord(
                name: record.name,
                ttl: record.ttl,
                ttlHuman: options.humanTTL ? TTLFormatter.humanReadable(record.ttl) : nil,
                class: record.recordClass.description,
                type: record.recordType.description,
                rdata: record.rdata.shortDescription,
                ptr: ptrAnnotation
            )
        }
    }

    private func buildMetadata(_ metadata: ResolutionMetadata) -> StructuredMetadata {
        let queryTimeMs = Int(metadata.queryTime.milliseconds)

        var ede: StructuredEDE?
        if let edeInfo = metadata.ednsInfo?.extendedDNSError {
            ede = StructuredEDE(
                infoCode: Int(edeInfo.infoCode),
                infoCodeName: edeInfo.infoCodeName ?? "Unknown",
                extraText: edeInfo.extraText
            )
        }

        return StructuredMetadata(
            responseCode: metadata.responseCode.description,
            queryTimeMs: queryTimeMs,
            resolver: metadata.resolverMode.description,
            ede: ede
        )
    }

    // MARK: - YAML encoding

    func encode(_ value: some Encodable) -> String {
        encodeYAML(value)
    }

    func encodeYAML(_ value: some Encodable) -> String {
        let encoder = YAMLEncoder()
        do {
            let output = try encoder.encode(value)
            // YAMLEncoder appends a trailing newline; trim it for consistency
            // with other formatters that don't add trailing newlines
            return output.hasSuffix("\n") ? String(output.dropLast()) : output
        } catch {
            FileHandle.standardError.write(Data("dug: YAML encoding failed: \(error)\n".utf8))
        }
        return "[]"
    }
}
