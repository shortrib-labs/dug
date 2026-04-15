import Foundation

/// Errors thrown by dug. NXDOMAIN and other DNS response codes are NOT errors —
/// they are metadata in ResolutionResult (exit code 0). Only operational and
/// usage failures are thrown.
enum DugError: Error, CustomStringConvertible {
    // Operational errors
    case timeout(name: String, seconds: Int)
    case networkError(underlying: Error)
    case serviceError(code: Int32)

    // Usage errors
    case invalidArgument(String)
    case unknownRecordType(String)
    case invalidAddress(String)
    case missingDomainName

    // Internal errors
    case rdataParseFailure(type: UInt16, dataLength: Int)
    case unexpectedState(String)

    var exitCode: Int32 {
        switch self {
        case .invalidArgument, .unknownRecordType, .invalidAddress, .missingDomainName:
            1 // usage error
        case .timeout:
            9 // no reply
        default:
            10 // internal error
        }
    }

    var description: String {
        switch self {
        case let .timeout(name, secs):
            ";; connection timed out; no servers could be reached (\(name), \(secs)s)"
        case let .networkError(err):
            ";; network error: \(err)"
        case let .serviceError(code):
            ";; DNS service error: \(code)"
        case let .invalidArgument(msg):
            "dug: invalid argument: \(msg)"
        case let .unknownRecordType(t):
            "dug: unknown record type: \(t)"
        case let .invalidAddress(addr):
            "dug: invalid address: \(addr)"
        case .missingDomainName:
            "dug: no domain name specified"
        case let .rdataParseFailure(type, len):
            "dug: failed to parse rdata for type \(type) (length \(len))"
        case let .unexpectedState(msg):
            "dug: internal error: \(msg)"
        }
    }
}

/// Equatable conformance for testing
extension DugError: Equatable {
    static func == (lhs: DugError, rhs: DugError) -> Bool {
        switch (lhs, rhs) {
        case let (.timeout(a, b), .timeout(c, d)): a == c && b == d
        case let (.invalidArgument(a), .invalidArgument(b)): a == b
        case let (.unknownRecordType(a), .unknownRecordType(b)): a == b
        case let (.invalidAddress(a), .invalidAddress(b)): a == b
        case (.missingDomainName, .missingDomainName): true
        case let (.serviceError(a), .serviceError(b)): a == b
        case let (.rdataParseFailure(a, b), .rdataParseFailure(c, d)): a == c && b == d
        default: false
        }
    }
}
