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
            1
        case .timeout:
            9
        default:
            10
        }
    }

    var description: String {
        switch self {
        case let .timeout(name, secs):
            ";; connection timed out; no servers could be reached (\(sanitize(name)), \(secs)s)"
        case let .networkError(err):
            ";; network error: \(err)"
        case let .serviceError(code):
            ";; DNS service error: \(code)"
        case let .invalidArgument(msg):
            "dug: invalid argument: \(sanitize(msg))"
        case let .unknownRecordType(t):
            "dug: unknown record type: \(sanitize(t))"
        case let .invalidAddress(addr):
            "dug: invalid address: \(sanitize(addr))"
        case .missingDomainName:
            "dug: no domain name specified"
        case let .rdataParseFailure(type, len):
            "dug: failed to parse rdata for type \(type) (length \(len))"
        case let .unexpectedState(msg):
            "dug: internal error: \(sanitize(msg))"
        }
    }
}

/// Strip control characters from user-supplied strings in error messages
/// to prevent terminal escape injection.
private func sanitize(_ s: String) -> String {
    String(s.unicodeScalars.map { scalar in
        if scalar.value < 0x20 || scalar.value == 0x7F {
            Character("?")
        } else {
            Character(scalar)
        }
    })
}
