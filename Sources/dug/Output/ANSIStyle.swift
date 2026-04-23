/// ANSI SGR escape codes for terminal styling.
enum ANSIStyle {
    case bold
    case dim
    case boldGreen

    func wrap(_ text: String) -> String {
        "\(open)\(text)\(ANSIStyle.reset)"
    }

    private var open: String {
        switch self {
        case .bold: "\u{1B}[1m"
        case .dim: "\u{1B}[2m"
        case .boldGreen: "\u{1B}[1;32m"
        }
    }

    private static let reset = "\u{1B}[0m"
}
