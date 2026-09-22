extension Dashboard {
    /// Unpaid bills falling due within `days` days, most urgent first.
    ///
    /// Distinct from ``notifications``, which uses each frequency's own `dueSoonThresholdDays` — a
    /// fortnightly bill warns three days out, a yearly one fourteen. This applies one flat window
    /// to every bill, because the daily push answers a single question: what do I owe this week?
    ///
    /// Overdue bills are included. Their `daysLeft` is negative, so they sort first and clear the
    /// threshold on their own; a bill nobody paid does not stop mattering the day after it was due.
    public func duePayments(within days: Int) -> [ExpenseSummary] {
        expenses
            .filter { $0.expense.active }
            .filter { $0.status != .paid && $0.status != .inactive }
            .filter { summary in
                guard let daysLeft = summary.daysLeft, summary.dueDate != nil else { return false }
                return daysLeft <= days
            }
            .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
    }
}

/// The daily push about bills coming due.
///
/// Plain text rather than HTML: this goes to ntfy, which renders a notification body, not a mail
/// client. Kept beside ``AlertEmail`` so both wordings stay in one place and in step.
public enum DueDigest {
    public static func title(count: Int, language: Language) -> String {
        switch language {
        case .pl: return "HomeBudget: \(Localization.alertCountLabel(count, language: .pl))"
        case .en: return "HomeBudget: \(count) payment\(count == 1 ? "" : "s") due"
        }
    }

    /// One line per bill: name, amount, and how long is left.
    ///
    /// `notificationMessage` only speaks for `overdue` and `dueSoon`, so a bill inside the window
    /// but still classed `upcoming` — which happens whenever the window is wider than that
    /// frequency's own threshold — gets its wording here instead of an empty string.
    public static func body(
        _ items: [Dashboard.ExpenseSummary],
        language: Language
    ) -> String {
        items.map { item -> String in
            let amount = NumberFormatting.currency(item.expense.amount, language: language)
            let daysLeft = item.daysLeft ?? 0
            let timing =
                item.status.isAlerting
                ? Localization.notificationMessage(
                    status: item.status, daysLeft: daysLeft, language: language)
                : upcomingMessage(daysLeft: daysLeft, language: language)

            return "• \(item.expense.name) — \(amount) — \(timing)"
        }
        .joined(separator: "\n")
    }

    private static func upcomingMessage(daysLeft: Int, language: Language) -> String {
        switch language {
        case .pl:
            if daysLeft == 0 { return "Termin dzisiaj" }
            return daysLeft == 1 ? "Termin za 1 dzień" : "Termin za \(daysLeft) dni"
        case .en:
            if daysLeft == 0 { return "Due today" }
            return daysLeft == 1 ? "Due in 1 day" : "Due in \(daysLeft) days"
        }
    }
}
