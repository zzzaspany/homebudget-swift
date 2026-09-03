/// A month laid out as calendar weeks, with the expenses falling due on each day.
///
/// Lives in the core rather than the web client so the iOS app can lay out the same month, and so
/// the "does this expense fall in this month" rule has one implementation to test.
public struct MonthGrid: Hashable, Sendable {
    public let year: Int
    public let month: Int
    public let days: [Day]
    /// Blank cells before the first of the month, so the grid starts on a Monday.
    public let leadingBlanks: Int

    public struct Day: Hashable, Sendable {
        public let date: CalendarDate
        public let entries: [Entry]
        public let isToday: Bool
    }

    public struct Entry: Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let amount: Double
        public let status: ExpenseStatus
    }

    public static func build(
        year: Int, month: Int, expenses: [Expense], today: CalendarDate
    ) -> MonthGrid {
        let first = CalendarDate(year: year, month: month, day: 1)
        let dayCount = CalendarDate.daysInMonth(year: year, month: month)

        let days = (1...dayCount).map { day -> Day in
            let date = CalendarDate(year: year, month: month, day: day)
            let entries = expenses.compactMap { expense -> Entry? in
                guard expense.active, falls(expense, on: date) else { return nil }
                return Entry(
                    id: expense.id,
                    name: expense.name,
                    amount: expense.amount,
                    status: StatusCalculator.status(for: expense, today: today).status
                )
            }
            return Day(date: date, entries: entries, isToday: date == today)
        }

        return MonthGrid(
            year: year,
            month: month,
            days: days,
            leadingBlanks: first.isoWeekday - 1
        )
    }

    /// Whether a recurring expense comes due on this particular date.
    static func falls(_ expense: Expense, on date: CalendarDate) -> Bool {
        // The nominal due day can exceed the length of a short month, in which case the expense
        // lands on the last day — the same clamping the status calculation applies.
        let dueDay = min(expense.dueDay, CalendarDate.daysInMonth(year: date.year, month: date.month))
        guard date.day == dueDay else { return false }

        switch expense.frequency {
        case .monthly, .biweekly:
            return true
        case .yearly:
            return expense.anchorMonth == date.month
        case .quarterly, .semiAnnual:
            guard let interval = expense.frequency.monthInterval else { return false }
            return (date.month - expense.anchorMonth) %% interval == 0
        }
    }

    public func adding(months offset: Int) -> (year: Int, month: Int) {
        let absolute = (year * 12 + month - 1) + offset
        return (absolute / 12, absolute % 12 + 1)
    }
}
