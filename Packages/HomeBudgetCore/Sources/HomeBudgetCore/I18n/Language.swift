public enum Language: String, Codable, CaseIterable, Sendable {
    case pl
    case en

    public init(code: String?) {
        self = Language(rawValue: (code ?? "").lowercased()) ?? .pl
    }

    var decimalSeparator: String { self == .pl ? "," : "." }
    var groupingSeparator: String { self == .pl ? "\u{00A0}" : "," }
}

public enum NumberFormatting {
    /// Formats an amount with two decimals and thousands grouping.
    ///
    /// Hand-rolled rather than `NumberFormatter`-based so the server and a WebAssembly build — where
    /// ICU locale data is not dependable — produce byte-identical output.
    public static func decimal(_ value: Double, language: Language) -> String {
        let rounded = (value * 100).rounded() / 100
        let isNegative = rounded < 0
        let cents = Int((abs(rounded) * 100).rounded())
        let whole = cents / 100
        let fraction = cents % 100

        var digits = String(whole)
        var grouped = ""
        while digits.count > 3 {
            let split = digits.index(digits.endIndex, offsetBy: -3)
            grouped = language.groupingSeparator + digits[split...] + grouped
            digits = String(digits[..<split])
        }
        grouped = digits + grouped

        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(isNegative ? "-" : "")\(grouped)\(language.decimalSeparator)\(fractionText)"
    }

    /// Amount with the currency marker, e.g. `1 234,56 zł` or `PLN 1,234.56`.
    public static func currency(_ value: Double, language: Language) -> String {
        switch language {
        case .pl: return "\(decimal(value, language: .pl))\u{00A0}zł"
        case .en: return "PLN \(decimal(value, language: .en))"
        }
    }
}
