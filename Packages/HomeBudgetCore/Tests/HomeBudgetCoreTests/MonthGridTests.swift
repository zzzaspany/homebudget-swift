import Testing

@testable import HomeBudgetCore

@Suite("Calendar month")
struct MonthGridTests {
    let today = CalendarDate(year: 2026, month: 9, day: 3)

    func expense(_ frequency: Frequency, dueDay: Int, dueMonth: Int? = nil, name: String = "Test") -> Expense {
        Expense(
            id: name, name: name, amount: 100, frequency: frequency, dueDay: dueDay,
            dueMonth: dueMonth, category: "Inne")
    }

    @Test("The grid covers the month and starts on a Monday")
    func shape() {
        let grid = MonthGrid.build(year: 2026, month: 9, expenses: [], today: today)
        #expect(grid.days.count == 30)
        // 1 September 2026 is a Tuesday, so one blank cell precedes it.
        #expect(grid.leadingBlanks == 1)

        let february = MonthGrid.build(year: 2024, month: 2, expenses: [], today: today)
        #expect(february.days.count == 29)
    }

    @Test("Today is marked exactly once")
    func todayMarker() {
        let grid = MonthGrid.build(year: 2026, month: 9, expenses: [], today: today)
        #expect(grid.days.filter(\.isToday).count == 1)
        #expect(grid.days.first(where: \.isToday)?.date.day == 3)

        let other = MonthGrid.build(year: 2026, month: 10, expenses: [], today: today)
        #expect(other.days.allSatisfy { !$0.isToday })
    }

    @Test("Monthly bills appear every month, yearly only in their month")
    func recurrence() {
        let rent = expense(.monthly, dueDay: 10, name: "Czynsz")
        let insurance = expense(.yearly, dueDay: 15, dueMonth: 11, name: "OC")

        let september = MonthGrid.build(year: 2026, month: 9, expenses: [rent, insurance], today: today)
        #expect(september.days[9].entries.map(\.name) == ["Czynsz"])
        #expect(september.days.allSatisfy { !$0.entries.contains { $0.name == "OC" } })

        let november = MonthGrid.build(year: 2026, month: 11, expenses: [rent, insurance], today: today)
        #expect(november.days[14].entries.map(\.name) == ["OC"])
    }

    @Test("Quarterly bills land every third month from their anchor")
    func quarterly() {
        let waste = expense(.quarterly, dueDay: 10, dueMonth: 1, name: "Śmieci")

        for month in [1, 4, 7, 10] {
            let grid = MonthGrid.build(year: 2026, month: month, expenses: [waste], today: today)
            #expect(grid.days[9].entries.count == 1, "expected a bill in month \(month)")
        }
        for month in [2, 3, 5, 6] {
            let grid = MonthGrid.build(year: 2026, month: month, expenses: [waste], today: today)
            #expect(grid.days.allSatisfy { $0.entries.isEmpty }, "expected no bill in month \(month)")
        }
    }

    @Test("A due day beyond the end of the month falls on its last day")
    func clampedDueDay() {
        let grid = MonthGrid.build(
            year: 2026, month: 2, expenses: [expense(.monthly, dueDay: 31)], today: today)
        #expect(grid.days[27].entries.count == 1)
        #expect(grid.days[27].date.day == 28)
    }

    @Test("Inactive expenses are left out")
    func inactiveExcluded() {
        var disabled = expense(.monthly, dueDay: 10)
        disabled.active = false
        let grid = MonthGrid.build(year: 2026, month: 9, expenses: [disabled], today: today)
        #expect(grid.days.allSatisfy { $0.entries.isEmpty })
    }

    @Test("Month stepping wraps across year boundaries")
    func stepping() {
        let december = MonthGrid.build(year: 2026, month: 12, expenses: [], today: today)
        #expect(december.adding(months: 1) == (2027, 1))

        let january = MonthGrid.build(year: 2026, month: 1, expenses: [], today: today)
        #expect(january.adding(months: -1) == (2025, 12))
    }
}
