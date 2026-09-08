/// One occurrence of a recurring expense: when it falls due, and the period marker that records it as paid.
struct Occurrence: Hashable, Sendable {
    let periodKey: String
    let dueDate: CalendarDate
}

/// Resolves which occurrence of a recurring expense is currently open, and which one follows it.
///
/// Both the status calculation and the "mark as paid" flow go through here, so a period stamped by a
/// payment is always in the format the status calculation compares against.
enum CycleResolver {
    static func current(for expense: Expense, today: CalendarDate) -> Occurrence {
        switch expense.frequency {
        case .monthly:
            return Occurrence(
                periodKey: PeriodKey.month(year: today.year, month: today.month),
                dueDate: .clamping(year: today.year, month: today.month, day: expense.dueDay)
            )

        case .biweekly:
            return Occurrence(
                periodKey: PeriodKey.week(on: today),
                dueDate: .clamping(year: today.year, month: today.month, day: expense.dueDay)
            )

        case .yearly:
            return Occurrence(
                periodKey: PeriodKey.year(today.year),
                dueDate: .clamping(year: today.year, month: expense.anchorMonth, day: expense.dueDay)
            )

        case .quarterly, .semiAnnual:
            let months = PeriodKey.cycleMonths(frequency: expense.frequency, anchorMonth: expense.anchorMonth)
            let month = months.first { $0 >= today.month } ?? months[0]
            let year = month >= today.month ? today.year : today.year + 1
            return Occurrence(
                periodKey: PeriodKey.month(year: year, month: month),
                dueDate: .clamping(year: year, month: month, day: expense.dueDay)
            )
        }
    }

    static func next(after current: Occurrence, for expense: Expense, today: CalendarDate) -> Occurrence {
        switch expense.frequency {
        case .monthly:
            let month = current.dueDate.month == 12 ? 1 : current.dueDate.month + 1
            let year = current.dueDate.month == 12 ? current.dueDate.year + 1 : current.dueDate.year
            return Occurrence(
                periodKey: PeriodKey.month(year: year, month: month),
                dueDate: .clamping(year: year, month: month, day: expense.dueDay)
            )

        case .biweekly:
            let dueDate = today.addingDays(14)
            return Occurrence(periodKey: PeriodKey.week(on: dueDate), dueDate: dueDate)

        case .yearly:
            let year = current.dueDate.year + 1
            return Occurrence(
                periodKey: PeriodKey.year(year),
                dueDate: .clamping(year: year, month: expense.anchorMonth, day: expense.dueDay)
            )

        case .quarterly, .semiAnnual:
            let months = PeriodKey.cycleMonths(frequency: expense.frequency, anchorMonth: expense.anchorMonth)
            let index = ((months.firstIndex(of: current.dueDate.month) ?? 0) + 1) % months.count
            let month = months[index]
            let year = index == 0 ? current.dueDate.year + 1 : current.dueDate.year
            return Occurrence(
                periodKey: PeriodKey.month(year: year, month: month),
                dueDate: .clamping(year: year, month: month, day: expense.dueDay)
            )
        }
    }
}

/// Works out where a bill stands: its status, its next due date, and how far away that is.
///
/// The invariant worth knowing is that a bill already paid for the current period reports
/// the date of its *next* occurrence, not the one just settled.
public enum StatusCalculator {
    /// Status, next due date and days remaining for one expense.
    ///
    /// An expense paid for its current cycle reports `.paid` together with the *next* due date,
    /// not the one that was just settled.
    public static func status(for expense: Expense, today: CalendarDate) -> ExpenseStatusResult {
        guard expense.active else {
            return ExpenseStatusResult(status: .inactive, dueDate: nil, daysLeft: nil)
        }

        let current = CycleResolver.current(for: expense, today: today)
        let isPaid = !expense.lastPaidPeriod.isEmpty && expense.lastPaidPeriod >= current.periodKey

        let dueDate: CalendarDate
        let status: ExpenseStatus
        if isPaid {
            dueDate = CycleResolver.next(after: current, for: expense, today: today).dueDate
            status = .paid
        } else {
            dueDate = current.dueDate
            let daysLeft = today.days(until: dueDate)
            if daysLeft < 0 {
                status = .overdue
            } else {
                status = daysLeft <= expense.frequency.dueSoonThresholdDays ? .dueSoon : .upcoming
            }
        }

        return ExpenseStatusResult(status: status, dueDate: dueDate, daysLeft: today.days(until: dueDate))
    }

    /// The period marker to stamp when recording a payment: the open cycle, or the following one
    /// if the open cycle is already settled.
    public static func targetPeriod(for expense: Expense, today: CalendarDate) -> String {
        let current = CycleResolver.current(for: expense, today: today)
        if expense.lastPaidPeriod.isEmpty || expense.lastPaidPeriod < current.periodKey {
            return current.periodKey
        }
        return CycleResolver.next(after: current, for: expense, today: today).periodKey
    }
}
