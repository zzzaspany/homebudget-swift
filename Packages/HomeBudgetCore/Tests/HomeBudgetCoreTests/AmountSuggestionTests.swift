import Testing

@testable import HomeBudgetCore

@Suite("Amount suggestions for variable bills")
struct AmountSuggestionTests {
    private func payment(_ year: Int, _ month: Int, _ amount: Double) -> Payment {
        Payment(
            id: "\(year)-\(month)", expenseID: "gas", amountPaid: amount,
            datePaid: CalendarDate(year: year, month: month, day: 10),
            period: "\(year)-\(month)", paidBy: "konrad")
    }

    /// A year of gas: expensive in winter, negligible in summer. The point of the whole feature.
    private var seasonal: PriceHistory {
        PriceHistory.build(
            expenseID: "gas",
            payments: [
                payment(2025, 1, 480), payment(2025, 4, 210), payment(2025, 7, 60),
                payment(2025, 10, 190), payment(2026, 1, 520), payment(2026, 4, 230),
            ])
    }

    @Test("The same month in an earlier year beats the overall average")
    func prefersSameMonth() throws {
        let suggestion = try #require(seasonal.suggestedAmount(forMonth: 7))
        #expect(suggestion.amount == 60)
        #expect(suggestion.basis == .sameMonth(CalendarDate(year: 2025, month: 7, day: 10)))

        // The average of everything would have suggested 281.67 for a July bill that has never
        // cost more than 60.
        let average = try #require(seasonal.averageAmountPaid)
        #expect(average > 250)
    }

    @Test("Several payments in the same month are averaged")
    func averagesSameMonth() throws {
        let suggestion = try #require(seasonal.suggestedAmount(forMonth: 1))
        #expect(suggestion.amount == 500)  // (480 + 520) / 2
        #expect(suggestion.basis == .sameMonthAverage(count: 2))
    }

    @Test("With nothing from that month, it falls back to the overall average")
    func fallsBack() throws {
        let suggestion = try #require(seasonal.suggestedAmount(forMonth: 12))
        #expect(suggestion.basis == .overallAverage(count: 6))
        #expect(suggestion.amount == seasonal.averageAmountPaid)
    }

    @Test("No history, no suggestion — better than inventing one")
    func noHistory() {
        let empty = PriceHistory.build(expenseID: "gas", payments: [])
        #expect(empty.suggestedAmount(forMonth: 1) == nil)
    }
}
