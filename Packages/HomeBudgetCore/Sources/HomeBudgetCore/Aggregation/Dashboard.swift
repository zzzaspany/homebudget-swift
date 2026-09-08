/// Everything the dashboard needs, derived from the raw expense list in one pass.
///
/// Values here are language-neutral (month numbers, day counts, raw category names); formatting and
/// translation happen in `I18n` so the server's reports and the client's UI cannot drift apart.
public struct Dashboard: Codable, Hashable, Sendable {
    public let kpis: KPIs
    public let expenses: [ExpenseSummary]
    public let categoryBreakdown: [CategoryShare]
    public let projection: [ProjectionEntry]
    public let notifications: [NotificationItem]
    public let sinkingFundItems: [SinkingFundItem]

    public struct KPIs: Codable, Hashable, Sendable {
        public let monthlyTotal: Double
        public let yearlyTotal: Double
        public let proRatedMonthly: Double
        public let sinkingFundTotal: Double
        public let overdueCount: Int
        public let dueSoonCount: Int

        enum CodingKeys: String, CodingKey {
            case monthlyTotal = "monthly_total"
            case yearlyTotal = "yearly_total"
            case proRatedMonthly = "pro_rated_monthly"
            case sinkingFundTotal = "sinking_fund_total"
            case overdueCount = "overdue_count"
            case dueSoonCount = "due_soon_count"
        }
    }

    public struct ExpenseSummary: Codable, Hashable, Sendable, Identifiable {
        public let expense: Expense
        public let status: ExpenseStatus
        public let dueDate: CalendarDate?
        public let daysLeft: Int?

        public var id: String { expense.id }
    }

    public struct CategoryShare: Codable, Hashable, Sendable {
        public let category: String
        public let proratedAmount: Double
    }

    public struct ProjectionEntry: Codable, Hashable, Sendable {
        public let year: Int
        public let month: Int
        public let amount: Double
    }

    public struct NotificationItem: Codable, Hashable, Sendable, Identifiable {
        public let id: String
        public let name: String
        public let status: ExpenseStatus
        public let amount: Double
        public let frequency: Frequency
        public let daysLeft: Int
        public let dueDate: CalendarDate?
    }

    public struct SinkingFundItem: Codable, Hashable, Sendable {
        public let name: String
        public let monthlyReserve: Double
        public let frequency: Frequency
        public let dueDate: CalendarDate?
    }
}

/// Derives every figure the dashboard shows from the raw expense list, in one pass.
extension Dashboard {
    /// The bills still to be paid, soonest first.
    ///
    /// Paid and inactive expenses are left out: this answers "what is coming", and something
    /// already settled is not. Overdue bills sort first because their `daysLeft` is negative, which
    /// is what you want — the most overdue is the most urgent.
    ///
    /// Lives here rather than in the widget that first needed it, so the rule has a test.
    public func upcoming(limit: Int) -> [ExpenseSummary] {
        guard limit > 0 else { return [] }
        return
            expenses
            .filter { $0.status != .paid && $0.status != .inactive }
            .filter { $0.dueDate != nil && $0.daysLeft != nil }
            .sorted { ($0.daysLeft ?? 0) < ($1.daysLeft ?? 0) }
            .prefix(limit)
            .map { $0 }
    }
}

public enum DashboardBuilder {
    public static func build(expenses: [Expense], today: CalendarDate) -> Dashboard {
        var summaries: [Dashboard.ExpenseSummary] = []
        var categoryTotals: [String: Double] = [:]
        var categoryOrder: [String] = []
        var sinkingFundItems: [Dashboard.SinkingFundItem] = []
        var notifications: [Dashboard.NotificationItem] = []

        var monthlyTotal = 0.0
        var yearlyTotal = 0.0
        var sinkingFundTotal = 0.0
        var overdueCount = 0
        var dueSoonCount = 0

        for expense in expenses {
            let result = StatusCalculator.status(for: expense, today: today)
            summaries.append(
                Dashboard.ExpenseSummary(
                    expense: expense,
                    status: result.status,
                    dueDate: result.dueDate,
                    daysLeft: result.daysLeft
                )
            )

            guard expense.active else { continue }

            switch result.status {
            case .overdue: overdueCount += 1
            case .dueSoon: dueSoonCount += 1
            default: break
            }

            if let daysLeft = result.daysLeft, result.status.isAlerting {
                notifications.append(
                    Dashboard.NotificationItem(
                        id: expense.id,
                        name: expense.name,
                        status: result.status,
                        amount: expense.amount,
                        frequency: expense.frequency,
                        daysLeft: daysLeft,
                        dueDate: result.dueDate
                    )
                )
            }

            switch expense.frequency {
            case .monthly: monthlyTotal += expense.amount
            case .yearly: yearlyTotal += expense.amount
            default: break
            }

            let prorated = expense.proratedMonthlyAmount
            if expense.frequency.needsSinkingFund {
                sinkingFundTotal += prorated
                sinkingFundItems.append(
                    Dashboard.SinkingFundItem(
                        name: expense.name,
                        monthlyReserve: prorated,
                        frequency: expense.frequency,
                        dueDate: result.dueDate
                    )
                )
            }

            if categoryTotals[expense.category] == nil {
                categoryOrder.append(expense.category)
            }
            categoryTotals[expense.category, default: 0] += prorated
        }

        notifications.sort { $0.daysLeft < $1.daysLeft }

        return Dashboard(
            kpis: Dashboard.KPIs(
                monthlyTotal: monthlyTotal,
                yearlyTotal: yearlyTotal,
                proRatedMonthly: monthlyTotal + sinkingFundTotal,
                sinkingFundTotal: sinkingFundTotal,
                overdueCount: overdueCount,
                dueSoonCount: dueSoonCount
            ),
            expenses: summaries,
            categoryBreakdown: categoryOrder.map {
                Dashboard.CategoryShare(category: $0, proratedAmount: categoryTotals[$0] ?? 0)
            },
            projection: projection(for: expenses, today: today),
            notifications: notifications,
            sinkingFundItems: sinkingFundItems
        )
    }

    /// Expected full (not prorated) outflow for each of the next 12 months.
    static func projection(for expenses: [Expense], today: CalendarDate) -> [Dashboard.ProjectionEntry] {
        (0..<12).map { offset in
            let absoluteMonth = today.month - 1 + offset
            let year = today.year + absoluteMonth / 12
            let month = absoluteMonth % 12 + 1

            let amount = expenses.reduce(into: 0.0) { total, expense in
                guard expense.active else { return }
                switch expense.frequency {
                case .monthly:
                    total += expense.amount
                case .yearly:
                    if expense.anchorMonth == month { total += expense.amount }
                case .quarterly, .semiAnnual:
                    guard let interval = expense.frequency.monthInterval else { return }
                    if (month - expense.anchorMonth) %% interval == 0 { total += expense.amount }
                case .biweekly:
                    break
                }
            }

            return Dashboard.ProjectionEntry(year: year, month: month, amount: amount)
        }
    }
}

infix operator %%: MultiplicationPrecedence

/// Modulo that is always non-negative, so month arithmetic works when the cycle anchor is later in the year.
func %% (lhs: Int, rhs: Int) -> Int {
    let remainder = lhs % rhs
    return remainder < 0 ? remainder + abs(rhs) : remainder
}
