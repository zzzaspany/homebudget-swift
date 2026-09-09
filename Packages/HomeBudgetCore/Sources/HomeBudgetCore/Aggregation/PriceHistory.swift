/// Payment history for a single expense, with the price drift between the first and latest payment.
public struct PriceHistory: Codable, Hashable, Sendable {
    public let expenseID: String
    public let totalRecords: Int
    public let priceChangePercent: Double
    public let entries: [Entry]

    public struct Entry: Codable, Hashable, Sendable {
        public let datePaid: CalendarDate
        public let amountPaid: Double
        public let period: String
    }

    public static func build(expenseID: String, payments: [Payment]) -> PriceHistory {
        let entries = payments
            .filter { $0.expenseID == expenseID }
            .sorted { $0.datePaid < $1.datePaid }
            .map { Entry(datePaid: $0.datePaid, amountPaid: $0.amountPaid, period: $0.period) }

        var changePercent = 0.0
        if let first = entries.first, let latest = entries.last, entries.count >= 2, first.amountPaid > 0 {
            let raw = (latest.amountPaid - first.amountPaid) / first.amountPaid * 100
            changePercent = (raw * 10).rounded() / 10
        }

        return PriceHistory(
            expenseID: expenseID,
            totalRecords: entries.count,
            priceChangePercent: changePercent,
            entries: entries
        )
    }

    /// Suggested amount for a variable bill: the average of everything paid so far.
    ///
    /// Kept because the web client shows it, but a poor guide on its own for anything seasonal —
    /// see ``suggestedAmount(forMonth:)``.
    public var averageAmountPaid: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + $1.amountPaid } / Double(entries.count)
    }

    /// What this bill is likely to come to in a given month, and on what grounds.
    ///
    /// Averaging a year of gas bills produces a number that is wrong in both directions: too low in
    /// January, too high in July. What the same month cost a year ago is a far better guess, so that
    /// is preferred whenever the history reaches back far enough.
    ///
    /// The basis is returned alongside the figure because a suggestion the user cannot account for
    /// is one they have to check anyway, which defeats the purpose of offering it.
    public func suggestedAmount(forMonth month: Int) -> AmountSuggestion? {
        let sameMonth = entries.filter { $0.datePaid.month == month }

        if sameMonth.count >= 2 {
            let total = sameMonth.reduce(0) { $0 + $1.amountPaid }
            return AmountSuggestion(
                amount: total / Double(sameMonth.count),
                basis: .sameMonthAverage(count: sameMonth.count))
        }

        if let only = sameMonth.first {
            return AmountSuggestion(amount: only.amountPaid, basis: .sameMonth(only.datePaid))
        }

        guard let average = averageAmountPaid else { return nil }
        return AmountSuggestion(amount: average, basis: .overallAverage(count: entries.count))
    }
}

/// A proposed amount, and why it was proposed.
public struct AmountSuggestion: Hashable, Sendable {
    public enum Basis: Hashable, Sendable {
        /// One earlier payment in the same calendar month.
        case sameMonth(CalendarDate)
        /// Several payments in the same calendar month, averaged.
        case sameMonthAverage(count: Int)
        /// Nothing from this month yet, so the whole history averaged.
        case overallAverage(count: Int)
    }

    public let amount: Double
    public let basis: Basis

    public init(amount: Double, basis: Basis) {
        self.amount = amount
        self.basis = basis
    }
}
