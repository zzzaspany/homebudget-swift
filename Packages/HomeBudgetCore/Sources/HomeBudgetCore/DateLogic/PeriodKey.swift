/// Period markers stamped on `Expense.lastPaidPeriod` and `Payment.period`.
///
/// The format is frequency-dependent and compared lexicographically, matching the Python app:
/// `"YYYY-MM"` for monthly/quarterly/semi-annual, `"YYYY"` for yearly, `"YYYY-Www"` for biweekly.
public enum PeriodKey {
    public static func month(year: Int, month: Int) -> String {
        "\(year)-\(CalendarDate.pad(month))"
    }

    public static func year(_ year: Int) -> String {
        "\(year)"
    }

    /// Biweekly keys pair the *calendar* year with the ISO week number, as the Python app does.
    public static func week(on date: CalendarDate) -> String {
        "\(date.year)-W\(CalendarDate.pad(date.isoWeek))"
    }

    /// The months of the year on which a month-aligned cycle falls, sorted ascending.
    static func cycleMonths(frequency: Frequency, anchorMonth: Int) -> [Int] {
        guard let interval = frequency.monthInterval, interval > 0 else { return [] }
        let occurrences = 12 / interval
        return (0..<occurrences)
            .map { (anchorMonth + interval * $0 - 1) % 12 + 1 }
            .sorted()
    }
}
