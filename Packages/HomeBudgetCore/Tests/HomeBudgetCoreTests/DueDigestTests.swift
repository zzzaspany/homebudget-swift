import Testing

@testable import HomeBudgetCore

@Suite("Due digest")
struct DueDigestTests {
    let today = CalendarDate(year: 2026, month: 8, day: 15)

    /// Due on the 17th — two days out, inside a five-day window.
    let internetBill = Expense(
        id: "due-soon", name: "Internet", amount: 120, frequency: .monthly, dueDay: 17,
        category: "Media i Eksploatacja")
    /// Due on the 10th — five days ago, so overdue.
    let rent = Expense(
        id: "overdue", name: "Czynsz", amount: 1000, frequency: .monthly, dueDay: 10,
        category: "Media i Eksploatacja")
    /// Due on the 28th — thirteen days out, well outside the window.
    let phone = Expense(
        id: "far-off", name: "Telefon", amount: 60, frequency: .monthly, dueDay: 28,
        category: "Media i Eksploatacja")

    private func dashboard(_ expenses: [Expense]) -> Dashboard {
        DashboardBuilder.build(expenses: expenses, today: today)
    }

    @Test("Only bills inside the window are selected")
    func windowSelectsNearTermBills() {
        let selected = dashboard([internetBill, rent, phone]).duePayments(within: 5)

        #expect(selected.map(\.expense.id) == ["overdue", "due-soon"])
    }

    /// The most overdue bill is the most urgent, and its days-left is negative, so it sorts first.
    @Test("Overdue bills come first")
    func overdueSortsFirst() {
        let selected = dashboard([internetBill, rent]).duePayments(within: 5)

        #expect(selected.first?.expense.id == "overdue")
        #expect((selected.first?.daysLeft ?? 0) < 0)
    }

    /// The whole point of the digest: something already settled must not be pushed about.
    @Test("Paid bills are left out")
    func paidBillsAreExcluded() {
        var paid = internetBill
        paid.lastPaidPeriod = PeriodKey.month(year: 2026, month: 8)

        let selected = dashboard([paid, phone]).duePayments(within: 5)

        #expect(selected.isEmpty)
    }

    @Test("Inactive bills are left out")
    func inactiveBillsAreExcluded() {
        var dormant = internetBill
        dormant.active = false

        #expect(dashboard([dormant]).duePayments(within: 5).isEmpty)
    }

    /// A window wider than the frequency's own `dueSoonThresholdDays` catches bills the dashboard
    /// still calls `upcoming`. Those have no `notificationMessage`, so the body must not go blank.
    @Test("Bills still classed upcoming get wording of their own")
    func upcomingBillsAreDescribed() {
        let quarterly = Expense(
            id: "quarterly", name: "Śmieci", amount: 300, frequency: .quarterly, dueDay: 19,
            dueMonth: 8, category: "Media i Eksploatacja")
        let selected = dashboard([quarterly]).duePayments(within: 5)

        #expect(selected.count == 1)
        let body = DueDigest.body(selected, language: .pl)
        #expect(body.contains("Śmieci"))
        #expect(body.contains("dni") || body.contains("dzień") || body.contains("dzisiaj"))
    }

    @Test("Body carries the name, amount and timing of every bill")
    func bodyDescribesEachBill() {
        let selected = dashboard([internetBill, rent]).duePayments(within: 5)
        let body = DueDigest.body(selected, language: .pl)

        #expect(body.split(separator: "\n").count == 2)
        #expect(body.contains("Internet"))
        #expect(body.contains("Czynsz"))
        #expect(body.contains(NumberFormatting.currency(1000, language: .pl)))
    }

    @Test("Title counts the bills in the language asked for")
    func titleIsLocalised() {
        #expect(DueDigest.title(count: 1, language: .en) == "HomeBudget: 1 payment due")
        #expect(DueDigest.title(count: 3, language: .en) == "HomeBudget: 3 payments due")
        #expect(DueDigest.title(count: 1, language: .pl).contains("1 alert"))
    }
}
