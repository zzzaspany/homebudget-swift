import Testing

@testable import HomeBudgetCore

/// Ports of `tests/test_date_calc.py` from the Python app, plus the cases it left uncovered.
@Suite("Expense status")
struct StatusCalculatorTests {
    let today = CalendarDate(year: 2026, month: 8, day: 15)

    func expense(
        _ frequency: Frequency,
        dueDay: Int,
        dueMonth: Int? = nil,
        lastPaid: String = "",
        active: Bool = true,
        amount: Double = 100
    ) -> Expense {
        Expense(
            id: "exp",
            name: "Test",
            amount: amount,
            frequency: frequency,
            dueDay: dueDay,
            dueMonth: dueMonth,
            category: "Inne",
            lastPaidPeriod: lastPaid,
            active: active
        )
    }

    @Test("Monthly: unpaid, paid and overdue")
    func monthly() {
        let dueSoon = StatusCalculator.status(
            for: expense(.monthly, dueDay: 20, lastPaid: "2026-07"), today: today)
        #expect(dueSoon.status == .dueSoon)
        #expect(dueSoon.daysLeft == 5)
        #expect(dueSoon.dueDate == CalendarDate(year: 2026, month: 8, day: 20))

        let paid = StatusCalculator.status(
            for: expense(.monthly, dueDay: 20, lastPaid: "2026-08"), today: today)
        #expect(paid.status == .paid)
        #expect(paid.dueDate == CalendarDate(year: 2026, month: 9, day: 20))

        let overdue = StatusCalculator.status(
            for: expense(.monthly, dueDay: 10, lastPaid: "2026-07"), today: today)
        #expect(overdue.status == .overdue)
        #expect(overdue.daysLeft == -5)
    }

    @Test("Monthly: paid in December rolls into the next year")
    func monthlyYearBoundary() {
        let december = CalendarDate(year: 2026, month: 12, day: 20)
        let result = StatusCalculator.status(
            for: expense(.monthly, dueDay: 15, lastPaid: "2026-12"), today: december)
        #expect(result.status == .paid)
        #expect(result.dueDate == CalendarDate(year: 2027, month: 1, day: 15))
    }

    @Test("Quarterly: cycles on the anchor month")
    func quarterly() {
        // Anchor January means Jan/Apr/Jul/Oct; in August the open occurrence is October.
        let upcoming = StatusCalculator.status(
            for: expense(.quarterly, dueDay: 10, dueMonth: 1, lastPaid: "2026-07"), today: today)
        #expect(upcoming.status == .upcoming)
        #expect(upcoming.dueDate == CalendarDate(year: 2026, month: 10, day: 10))

        let paid = StatusCalculator.status(
            for: expense(.quarterly, dueDay: 10, dueMonth: 1, lastPaid: "2026-10"), today: today)
        #expect(paid.status == .paid)
        #expect(paid.dueDate == CalendarDate(year: 2027, month: 1, day: 10))
    }

    @Test("Semi-annual: cycles every six months")
    func semiAnnual() {
        let upcoming = StatusCalculator.status(
            for: expense(.semiAnnual, dueDay: 20, dueMonth: 5, lastPaid: "2026-05"), today: today)
        #expect(upcoming.status == .upcoming)
        #expect(upcoming.dueDate == CalendarDate(year: 2026, month: 11, day: 20))

        let paid = StatusCalculator.status(
            for: expense(.semiAnnual, dueDay: 20, dueMonth: 5, lastPaid: "2026-11"), today: today)
        #expect(paid.status == .paid)
        #expect(paid.dueDate == CalendarDate(year: 2027, month: 5, day: 20))
    }

    @Test("Yearly: period marker is a bare year")
    func yearly() {
        let upcoming = StatusCalculator.status(
            for: expense(.yearly, dueDay: 1, dueMonth: 11, lastPaid: "2025"), today: today)
        #expect(upcoming.status == .upcoming)
        #expect(upcoming.dueDate == CalendarDate(year: 2026, month: 11, day: 1))

        let paid = StatusCalculator.status(
            for: expense(.yearly, dueDay: 1, dueMonth: 11, lastPaid: "2026"), today: today)
        #expect(paid.status == .paid)
        #expect(paid.dueDate == CalendarDate(year: 2027, month: 11, day: 1))
    }

    @Test("Biweekly: period marker is an ISO week")
    func biweekly() {
        let unpaid = StatusCalculator.status(
            for: expense(.biweekly, dueDay: 17, lastPaid: "2026-W32"), today: today)
        #expect(unpaid.status == .dueSoon)
        #expect(unpaid.dueDate == CalendarDate(year: 2026, month: 8, day: 17))

        let paid = StatusCalculator.status(
            for: expense(.biweekly, dueDay: 17, lastPaid: "2026-W33"), today: today)
        #expect(paid.status == .paid)
        #expect(paid.dueDate == today.addingDays(14))
    }

    @Test("Inactive expenses short-circuit everything")
    func inactive() {
        let result = StatusCalculator.status(
            for: expense(.monthly, dueDay: 1, active: false), today: today)
        #expect(result.status == .inactive)
        #expect(result.dueDate == nil)
        #expect(result.daysLeft == nil)
    }

    @Test("Due-soon thresholds differ per frequency")
    func dueSoonThresholds() {
        // A yearly bill 14 days out is "due soon"; a monthly one at the same distance is not.
        let yearly = StatusCalculator.status(
            for: expense(.yearly, dueDay: 29, dueMonth: 8, lastPaid: "2025"), today: today)
        #expect(yearly.daysLeft == 14)
        #expect(yearly.status == .dueSoon)

        let monthly = StatusCalculator.status(
            for: expense(.monthly, dueDay: 29, lastPaid: "2026-07"), today: today)
        #expect(monthly.daysLeft == 14)
        #expect(monthly.status == .upcoming)
    }

    @Test("Due day is clamped to the length of the month")
    func dueDayClamping() {
        let february = CalendarDate(year: 2026, month: 2, day: 1)
        let result = StatusCalculator.status(
            for: expense(.monthly, dueDay: 31, lastPaid: "2026-01"), today: february)
        #expect(result.dueDate == CalendarDate(year: 2026, month: 2, day: 28))
    }

    /// The Python app stamped a bare year on every non-monthly payment, which its own status
    /// calculation then failed to recognise — a quarterly bill could never read as paid.
    @Test("Payment periods are stamped in the format the status check compares against")
    func targetPeriodMatchesStatusFormat() {
        let quarterly = expense(.quarterly, dueDay: 10, dueMonth: 1)
        let period = StatusCalculator.targetPeriod(for: quarterly, today: today)
        #expect(period == "2026-10")

        var settled = quarterly
        settled.lastPaidPeriod = period
        #expect(StatusCalculator.status(for: settled, today: today).status == .paid)

        // Paying again moves on to the following occurrence.
        #expect(StatusCalculator.targetPeriod(for: settled, today: today) == "2027-01")
    }

    @Test("Payment periods for every frequency")
    func targetPeriodPerFrequency() {
        #expect(StatusCalculator.targetPeriod(for: expense(.monthly, dueDay: 10), today: today) == "2026-08")
        #expect(
            StatusCalculator.targetPeriod(
                for: expense(.monthly, dueDay: 10, lastPaid: "2026-08"), today: today) == "2026-09")
        #expect(
            StatusCalculator.targetPeriod(
                for: expense(.yearly, dueDay: 1, dueMonth: 11), today: today) == "2026")
        #expect(
            StatusCalculator.targetPeriod(
                for: expense(.yearly, dueDay: 1, dueMonth: 11, lastPaid: "2026"), today: today) == "2027")
        #expect(StatusCalculator.targetPeriod(for: expense(.biweekly, dueDay: 17), today: today) == "2026-W33")
    }
}
