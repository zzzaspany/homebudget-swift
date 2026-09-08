/// A warning worth raising before a bill falls due, and the day to raise it on.
///
/// Separate from `Dashboard.NotificationItem`, which describes what already needs attention *now*.
/// This is the forward-looking version: what to schedule, and when.
public struct DueReminder: Hashable, Sendable, Identifiable {
    public let expenseID: String
    public let name: String
    public let amount: Double
    public let dueDate: CalendarDate
    /// The day the warning should appear — `dueSoonThresholdDays` before the bill is due.
    public let fireDate: CalendarDate
    public let daysBefore: Int

    public var id: String { expenseID }

    public init(
        expenseID: String, name: String, amount: Double, dueDate: CalendarDate,
        fireDate: CalendarDate, daysBefore: Int
    ) {
        self.expenseID = expenseID
        self.name = name
        self.amount = amount
        self.dueDate = dueDate
        self.fireDate = fireDate
        self.daysBefore = daysBefore
    }
}

extension Dashboard {
    /// Warnings to schedule, soonest first.
    ///
    /// The lead time is the cycle's own `dueSoonThresholdDays`, so a fortnightly bill warns three
    /// days out and a yearly one fourteen — the same thresholds the dashboard colours by, rather
    /// than a second opinion about what "soon" means.
    ///
    /// Anything whose warning day has already passed is left out. A notification cannot be
    /// scheduled into the past, and a bill that is already overdue is being shouted about by the
    /// dashboard, the widget and the e-mail alerts; a fourth voice saying the same thing a day late
    /// adds nothing.
    ///
    /// `limit` exists because iOS keeps at most 64 pending local notifications per app and silently
    /// drops the rest. Callers should stay well under that.
    public func dueReminders(after today: CalendarDate, limit: Int) -> [DueReminder] {
        guard limit > 0 else { return [] }

        return
            expenses
            .filter { $0.status != .paid && $0.status != .inactive }
            .compactMap { summary -> DueReminder? in
                guard let due = summary.dueDate else { return nil }
                let lead = summary.expense.frequency.dueSoonThresholdDays
                let fire = due.addingDays(-lead)
                guard fire > today else { return nil }

                return DueReminder(
                    expenseID: summary.expense.id, name: summary.expense.name,
                    amount: summary.expense.amount, dueDate: due, fireDate: fire,
                    daysBefore: lead)
            }
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(limit)
            .map { $0 }
    }
}
