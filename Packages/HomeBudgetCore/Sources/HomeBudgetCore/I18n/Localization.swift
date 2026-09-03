/// The single source of truth for every user-facing label.
///
/// The Python app kept three drifting copies of these maps (`app.js`, `report_generator.py`,
/// the CSV writer in `main.py`); server reports and client UI both read from here instead.
public enum Localization {
    // MARK: - Months

    static let monthAbbreviationsPL = [
        "Sty", "Lut", "Mar", "Kwi", "Maj", "Cze", "Lip", "Sie", "Wrz", "Paź", "Lis", "Gru",
    ]
    static let monthAbbreviationsEN = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    public static func monthAbbreviation(_ month: Int, language: Language) -> String {
        guard (1...12).contains(month) else { return "" }
        return (language == .pl ? monthAbbreviationsPL : monthAbbreviationsEN)[month - 1]
    }

    /// Chart axis label for a projected month, e.g. `Sie '26`.
    public static func projectionLabel(year: Int, month: Int, language: Language) -> String {
        let shortYear = String(String(year).suffix(2))
        return "\(monthAbbreviation(month, language: language)) '\(shortYear)"
    }

    /// A date for display: `20 Sie 2026` in Polish, `Aug 20, 2026` in English.
    public static func dateLabel(_ date: CalendarDate, language: Language) -> String {
        let month = monthAbbreviation(date.month, language: language)
        switch language {
        case .pl: return "\(date.day) \(month) \(date.year)"
        case .en: return "\(month) \(date.day), \(date.year)"
        }
    }

    /// Renders a stored period marker for display: `2026-08` becomes `Sie 2026`, `2026` stays as is.
    public static func periodLabel(_ period: String, language: Language) -> String {
        let parts = period.split(separator: "-")
        guard parts.count == 2, let month = Int(parts[1]), (1...12).contains(month) else {
            return period
        }
        return "\(monthAbbreviation(month, language: language)) \(parts[0])"
    }

    // MARK: - Categories

    /// Categories are free text entered in Polish; this maps the well-known ones to English.
    static let categoryPLtoEN = [
        "Serwisy i Przeglądy": "Maintenance & Inspections",
        "Bufor i Rezerwy": "Buffer & Reserves",
        "Media i Eksploatacja": "Utilities & Operations",
        "Podatki": "Taxes",
        "Kredyt i Ubezpieczenia": "Loans & Insurance",
        "Inne": "Other",
        "Stałe Opłaty": "Fixed Fees",
        "Podatki i Ubezpieczenia": "Taxes & Insurance",
    ]

    public static func category(_ name: String, language: Language) -> String {
        language == .pl ? name : (categoryPLtoEN[name] ?? name)
    }

    // MARK: - Notifications

    public static func notificationMessage(
        status: ExpenseStatus,
        daysLeft: Int,
        language: Language
    ) -> String {
        switch (status, language) {
        case (.overdue, .pl):
            let days = -daysLeft
            return days == 1 ? "Po terminie o 1 dzień" : "Po terminie o \(days) dni"
        case (.overdue, .en):
            let days = -daysLeft
            return days == 1 ? "Overdue by 1 day" : "Overdue by \(days) days"
        case (.dueSoon, .pl):
            return daysLeft == 1 ? "Termin za 1 dzień" : "Termin za \(daysLeft) dni"
        case (.dueSoon, .en):
            return daysLeft == 1 ? "Due in 1 day" : "Due in \(daysLeft) days"
        default:
            return ""
        }
    }

    /// Polish needs three alert-count forms (1 alert / 2-4 alerty / 5+ alertów).
    public static func alertCountLabel(_ count: Int, language: Language) -> String {
        guard language == .pl else { return count == 1 ? "1 alert" : "\(count) alerts" }
        let lastTwo = count % 100
        let last = count % 10
        if count == 1 { return "1 alert" }
        if (2...4).contains(last) && !(12...14).contains(lastTwo) { return "\(count) alerty" }
        return "\(count) alertów"
    }
}

extension Frequency {
    public func label(language: Language) -> String {
        switch (self, language) {
        case (.monthly, .pl): return "Miesięczny"
        case (.biweekly, .pl): return "Co 2 tyg"
        case (.quarterly, .pl): return "Kwartalny"
        case (.semiAnnual, .pl): return "Półroczny"
        case (.yearly, .pl): return "Roczny"
        case (.monthly, .en): return "Monthly"
        case (.biweekly, .en): return "Biweekly"
        case (.quarterly, .en): return "Quarterly"
        case (.semiAnnual, .en): return "Semi-annual"
        case (.yearly, .en): return "Yearly"
        }
    }
}

extension ExpenseStatus {
    /// Upper-case form used in CSV and PDF reports.
    public func reportLabel(language: Language) -> String {
        switch (self, language) {
        case (.paid, .pl): return "OPŁACONE"
        case (.overdue, .pl): return "ZALEGŁE"
        case (.dueSoon, .pl): return "WKRÓTCE"
        case (.upcoming, .pl): return "NADCHODZĄCE"
        case (.inactive, .pl): return "NIEAKTYWNE"
        case (.paid, .en): return "PAID"
        case (.overdue, .en): return "OVERDUE"
        case (.dueSoon, .en): return "DUE SOON"
        case (.upcoming, .en): return "UPCOMING"
        case (.inactive, .en): return "INACTIVE"
        }
    }
}
