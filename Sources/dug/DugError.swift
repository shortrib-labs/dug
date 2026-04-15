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
            return 1  // usage error
        case .timeout:
            return 9  // no reply
        default:
            return 10 // internal error
        }
    }

    var description: String {
        switch self {
        case .timeout(let name, let secs):
            return ";; connection timed out; no servers could be reached (\(name), \(secs)s)"
        case .networkError(let err):
            return ";; network error: \(err)"
        case .serviceError(let code):
            return ";; DNS service error: \(code)"
        case .invalidArgument(let msg):
            return "dug: invalid argument: \(msg)"
        case .unknownRecordType(let t):
            return "dug: unknown record type: \(t)"
        case .invalidAddress(let addr):
            return "dug: invalid address: \(addr)"
        case .missingDomainName:
            return "dug: no domain name specified"
        case .rdataParseFailure(let type, let len):
            return "dug: failed to parse rdata for type \(type) (length \(len))"
        case .unexpectedState(let msg):
            return "dug: internal error: \(msg)"
        }
    }
}

// Equatable conformance for testing
extension DugError: Equatable {
    static func == (lhs: DugError, rhs: DugError) -> Bool {
        switch (lhs, rhs) {
        case (.timeout(let a, let b), .timeout(let c, let d)): return a == c && b == d
        case (.invalidArgument(let a), .invalidArgument(let b)): return a == b
        case (.unknownRecordType(let a), .unknownRecordType(let b)): return a == b
        case (.invalidAddress(let a), .invalidAddress(let b)): return a == b
        case (.missingDomainName, .missingDomainName): return true
        case (.serviceError(let a), .serviceError(let b)): return a == b
        case (.rdataParseFailure(let a, let b), .rdataParseFailure(let c, let d)): return a == c && b == d
        default: return false
        }
    }
}
