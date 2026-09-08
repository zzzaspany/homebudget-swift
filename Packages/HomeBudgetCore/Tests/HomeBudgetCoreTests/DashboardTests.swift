import Testing

@testable import HomeBudgetCore

/// Port of `tests/test_sinking_funds.py`, extended with the biweekly proration the Python app dropped.
@Suite("Dashboard aggregation")
struct DashboardTests {
    let today = CalendarDate(year: 2026, month: 8, day: 15)

    let rent = Expense(
        id: "exp1", name: "Czynsz", amount: 1000, frequency: .monthly, dueDay: 10,
        category: "Media i Eksploatacja")
    let insurance = Expense(
        id: "exp2", name: "Ubezpieczenie OC", amount: 1200, frequency: .yearly, dueDay: 15,
        dueMonth: 5, category: "Podatki")
    let waste = Expense(
        id: "exp3", name: "Śmieci", amount: 300, frequency: .quarterly, dueDay: 1,
        dueMonth: 1, category: "Media i Eksploatacja")

    @Test("KPI totals across mixed frequencies")
    func kpis() {
        let dashboard = DashboardBuilder.build(expenses: [rent, insurance, waste], today: today)

        #expect(dashboard.kpis.monthlyTotal == 1000)
        #expect(dashboard.kpis.yearlyTotal == 1200)
        // 1000 monthly + 1200/12 yearly + 300/3 quarterly
        #expect(dashboard.kpis.proRatedMonthly == 1200)
        #expect(dashboard.kpis.sinkingFundTotal == 200)
        #expect(dashboard.sinkingFundItems.count == 2)
    }

    /// The Python app counted biweekly expenses in the category chart but left them out of every
    /// KPI, so a fortnightly bill silently vanished from the monthly budget.
    @Test("Biweekly expenses are prorated into the KPIs")
    func biweeklyIsProrated() {
        let internet = Expense(
            id: "exp4", name: "Internet", amount: 120, frequency: .biweekly, dueDay: 17,
            category: "Media i Eksploatacja")
        let dashboard = DashboardBuilder.build(expenses: [rent, internet], today: today)

        let expectedReserve = 120.0 * 26.0 / 12.0
        #expect(dashboard.kpis.sinkingFundTotal == expectedReserve)
        #expect(dashboard.kpis.proRatedMonthly == 1000 + expectedReserve)
        #expect(dashboard.sinkingFundItems.contains { $0.name == "Internet" })
    }

    @Test("Inactive expenses are listed but excluded from every total")
    func inactiveExcluded() {
        var disabled = insurance
        disabled.active = false
        let dashboard = DashboardBuilder.build(expenses: [rent, disabled], today: today)

        #expect(dashboard.expenses.count == 2)
        #expect(dashboard.kpis.yearlyTotal == 0)
        #expect(dashboard.kpis.proRatedMonthly == 1000)
        #expect(dashboard.sinkingFundItems.isEmpty)
        #expect(dashboard.categoryBreakdown.count == 1)
    }

    @Test("Category breakdown sums prorated amounts per category")
    func categoryBreakdown() {
        let dashboard = DashboardBuilder.build(expenses: [rent, insurance, waste], today: today)

        let utilities = dashboard.categoryBreakdown.first { $0.category == "Media i Eksploatacja" }
        let taxes = dashboard.categoryBreakdown.first { $0.category == "Podatki" }
        #expect(utilities?.proratedAmount == 1100)  // 1000 rent + 300/3 waste
        #expect(taxes?.proratedAmount == 100)  // 1200/12
    }

    @Test("Projection charges full amounts in the months they fall due")
    func projection() {
        let dashboard = DashboardBuilder.build(expenses: [rent, insurance, waste], today: today)
        #expect(dashboard.projection.count == 12)

        #expect(dashboard.projection[0].year == 2026)
        #expect(dashboard.projection[0].month == 8)
        #expect(dashboard.projection[0].amount == 1000)  // rent only

        // October is a quarterly month for the waste bill.
        let october = dashboard.projection.first { $0.month == 10 && $0.year == 2026 }
        #expect(october?.amount == 1300)

        // The yearly insurance lands in May of the following year.
        let may = dashboard.projection.first { $0.month == 5 && $0.year == 2027 }
        #expect(may?.amount == 2200)
    }

    @Test("Notifications cover alerting expenses, most urgent first")
    func notifications() {
        let overdue = Expense(
            id: "a", name: "Prąd", amount: 200, frequency: .monthly, dueDay: 5,
            category: "Media i Eksploatacja", lastPaidPeriod: "2026-07")
        let dueSoon = Expense(
            id: "b", name: "Woda", amount: 80, frequency: .monthly, dueDay: 18,
            category: "Media i Eksploatacja", lastPaidPeriod: "2026-07")
        let settled = Expense(
            id: "c", name: "Gaz", amount: 90, frequency: .monthly, dueDay: 20,
            category: "Media i Eksploatacja", lastPaidPeriod: "2026-08")

        let dashboard = DashboardBuilder.build(expenses: [dueSoon, settled, overdue], today: today)

        #expect(dashboard.notifications.map(\.id) == ["a", "b"])
        #expect(dashboard.kpis.overdueCount == 1)
        #expect(dashboard.kpis.dueSoonCount == 1)
    }

    @Test("Price history reports drift between first and latest payment")
    func priceHistory() {
        let payments = [
            Payment(
                id: "p2", expenseID: "exp1", amountPaid: 250,
                datePaid: CalendarDate(year: 2026, month: 7, day: 3), period: "2026-07", paidBy: "konrad"),
            Payment(
                id: "p1", expenseID: "exp1", amountPaid: 200,
                datePaid: CalendarDate(year: 2026, month: 1, day: 3), period: "2026-01", paidBy: "konrad"),
            Payment(
                id: "p3", expenseID: "other", amountPaid: 999,
                datePaid: CalendarDate(year: 2026, month: 7, day: 3), period: "2026-07", paidBy: "konrad"),
        ]

        let history = PriceHistory.build(expenseID: "exp1", payments: payments)
        #expect(history.totalRecords == 2)
        #expect(history.priceChangePercent == 25.0)
        #expect(history.entries.first?.amountPaid == 200)
        #expect(history.averageAmountPaid == 225)
    }

    @Test("Price history needs two payments before reporting drift")
    func priceHistorySinglePayment() {
        let payments = [
            Payment(
                id: "p1", expenseID: "exp1", amountPaid: 200,
                datePaid: CalendarDate(year: 2026, month: 1, day: 3), period: "2026-01", paidBy: "konrad")
        ]
        let history = PriceHistory.build(expenseID: "exp1", payments: payments)
        #expect(history.priceChangePercent == 0)
        #expect(history.averageAmountPaid == 200)
    }
}

@Suite("Upcoming bills")
struct UpcomingTests {
    private let today = CalendarDate(year: 2026, month: 9, day: 8)

    private func expense(
        _ id: String, day: Int, paidPeriod: String = "", active: Bool = true
    ) -> Expense {
        Expense(
            id: id, name: "Expense \(id)", amount: 100, frequency: .monthly, dueDay: day,
            category: "Inne", lastPaidPeriod: paidPeriod, active: active)
    }

    @Test("Nearest first, and the most overdue before that")
    func ordering() {
        let dashboard = DashboardBuilder.build(
            expenses: [expense("later", day: 20), expense("overdue", day: 1),
                       expense("soon", day: 10)],
            today: today)

        #expect(dashboard.upcoming(limit: 5).map(\.expense.id) == ["overdue", "soon", "later"])
    }

    @Test("Paid and inactive bills are not upcoming")
    func excluded() {
        let dashboard = DashboardBuilder.build(
            expenses: [expense("open", day: 20),
                       expense("paid", day: 21, paidPeriod: "2026-09"),
                       expense("off", day: 22, active: false)],
            today: today)

        #expect(dashboard.upcoming(limit: 5).map(\.expense.id) == ["open"])
    }

    @Test("The limit is honoured, and a non-positive one yields nothing")
    func limits() {
        let dashboard = DashboardBuilder.build(
            expenses: (1...6).map { expense("\($0)", day: $0 + 10) }, today: today)

        #expect(dashboard.upcoming(limit: 4).count == 4)
        #expect(dashboard.upcoming(limit: 0).isEmpty)
        #expect(dashboard.upcoming(limit: -1).isEmpty)
    }

    @Test("Every entry carries the date and countdown a caller needs")
    func completeness() {
        let dashboard = DashboardBuilder.build(expenses: [expense("a", day: 20)], today: today)
        let first = try! #require(dashboard.upcoming(limit: 1).first)

        #expect(first.dueDate == CalendarDate(year: 2026, month: 9, day: 20))
        #expect(first.daysLeft == 12)
    }
}

@Suite("Category budgets")
struct CategoryBudgetTests {
    @Test("A ceiling that is not set leaves the bar undrawn rather than empty")
    func noLimit() {
        let budget = CategoryBudget(category: "Inne", planned: 120, limit: nil)
        #expect(budget.fraction == nil)
        #expect(budget.isOverBudget == false)
        #expect(budget.overspend == 0)
    }

    @Test("Spend under, at and over the ceiling")
    func fractions() {
        #expect(CategoryBudget(category: "a", planned: 50, limit: 200).fraction == 0.25)
        #expect(CategoryBudget(category: "a", planned: 200, limit: 200).fraction == 1)
        // Clamped, so the bar cannot overrun its track — the overspend is reported separately.
        #expect(CategoryBudget(category: "a", planned: 300, limit: 200).fraction == 1)
        #expect(CategoryBudget(category: "a", planned: 300, limit: 200).overspend == 100)
        #expect(CategoryBudget(category: "a", planned: 300, limit: 200).isOverBudget)
    }

    @Test("A zero or negative ceiling is treated as unset, not as always exceeded")
    func degenerateLimits() {
        #expect(CategoryBudget(category: "a", planned: 10, limit: 0).fraction == nil)
        #expect(CategoryBudget(category: "a", planned: 10, limit: 0).isOverBudget == false)
        #expect(CategoryBudget(category: "a", planned: 10, limit: -5).isOverBudget == false)
    }

    @Test("Categories come back largest first, carrying their limits")
    func ordering() {
        let today = CalendarDate(year: 2026, month: 9, day: 8)
        let dashboard = DashboardBuilder.build(
            expenses: [
                Expense(id: "1", name: "small", amount: 50, frequency: .monthly, dueDay: 1,
                        category: "Inne"),
                Expense(id: "2", name: "big", amount: 500, frequency: .monthly, dueDay: 1,
                        category: "Podatki"),
            ],
            today: today)

        let budgets = dashboard.categoryBudgets(limits: ["Podatki": 400])
        #expect(budgets.map(\.category) == ["Podatki", "Inne"])
        #expect(budgets[0].isOverBudget)
        #expect(budgets[1].limit == nil)
    }
}

@Suite("Due reminders")
struct DueReminderTests {
    private let today = CalendarDate(year: 2026, month: 9, day: 8)

    private func expense(
        _ id: String, day: Int, frequency: Frequency = .monthly, month: Int? = nil,
        paidPeriod: String = "", active: Bool = true
    ) -> Expense {
        Expense(
            id: id, name: "Expense \(id)", amount: 100, frequency: frequency, dueDay: day,
            dueMonth: month, category: "Inne", lastPaidPeriod: paidPeriod, active: active)
    }

    @Test("The lead time is the cycle's own due-soon threshold")
    func leadTime() {
        // Monthly warns 5 days out, yearly 14.
        let dashboard = DashboardBuilder.build(
            expenses: [expense("m", day: 25),
                       expense("y", day: 25, frequency: .yearly, month: 12)],
            today: today)
        let byID = Dictionary(
            uniqueKeysWithValues: dashboard.dueReminders(after: today, limit: 10)
                .map { ($0.expenseID, $0) })

        #expect(byID["m"]?.daysBefore == 5)
        #expect(byID["m"]?.fireDate == CalendarDate(year: 2026, month: 9, day: 20))
        #expect(byID["y"]?.daysBefore == 14)
        #expect(byID["y"]?.fireDate == CalendarDate(year: 2026, month: 12, day: 11))
    }

    @Test("A warning day already past is not scheduled")
    func noPastWarnings() {
        // Due on the 10th, monthly, so the warning day was the 5th — three days ago.
        let dashboard = DashboardBuilder.build(expenses: [expense("late", day: 10)], today: today)
        #expect(dashboard.dueReminders(after: today, limit: 10).isEmpty)
    }

    @Test("Paid and inactive bills raise nothing")
    func excluded() {
        let dashboard = DashboardBuilder.build(
            expenses: [expense("open", day: 25),
                       expense("paid", day: 26, paidPeriod: "2026-09"),
                       expense("off", day: 27, active: false)],
            today: today)
        #expect(dashboard.dueReminders(after: today, limit: 10).map(\.expenseID) == ["open"])
    }

    @Test("Soonest first, and the limit is honoured")
    func orderingAndLimit() {
        let dashboard = DashboardBuilder.build(
            expenses: [expense("c", day: 28), expense("a", day: 20), expense("b", day: 24)],
            today: today)

        #expect(dashboard.dueReminders(after: today, limit: 10).map(\.expenseID) == ["a", "b", "c"])
        #expect(dashboard.dueReminders(after: today, limit: 2).map(\.expenseID) == ["a", "b"])
        #expect(dashboard.dueReminders(after: today, limit: 0).isEmpty)
    }
}
