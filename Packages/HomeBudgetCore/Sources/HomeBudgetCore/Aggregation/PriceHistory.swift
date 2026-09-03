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
    public var averageAmountPaid: Double? {
        guard !entries.isEmpty else { return nil }
        return entries.reduce(0) { $0 + $1.amountPaid } / Double(entries.count)
    }
}
