import EventKit
import Foundation
import HomeBudgetCore

/// Shared plumbing between the two EventKit features: the reminder export and the per-expense
/// calendar event.
///
/// One `EKEventStore` for the whole app. Creating a second one is not an error but it is wasteful,
/// and identifiers handed out by one store are not meaningful to another.
@MainActor
enum EventKitBridge {
    static let store = EKEventStore()

    /// The hour a bill is due at. Nothing in the domain has a time of day, so one is chosen —
    /// morning, when there is still a working day left to pay it in.
    static let dueHour = 9

    /// Turns a `CalendarDate` into the components a reminder's due date needs.
    ///
    /// The time matters more than it looks. A reminder whose due date carries no time is treated as
    /// undated-with-a-day, and EventKit then surfaces whatever absolute alarm is attached as the
    /// item's date — which put every bill on screen `dueSoonThresholdDays` early, and made the
    /// recurrence rule follow the wrong day of the month with it.
    static func dueComponents(_ date: CalendarDate) -> DateComponents {
        DateComponents(
            year: date.year, month: date.month, day: date.day, hour: dueHour, minute: 0)
    }

    /// A concrete `Date` at midday local time, for the APIs that insist on one.
    ///
    /// Midday rather than midnight so a daylight-saving shift cannot move it into the day before.
    static func date(_ date: CalendarDate) -> Date? {
        Calendar.current.date(
            from: DateComponents(
                year: date.year, month: date.month, day: date.day, hour: 12, minute: 0))
    }

    /// The recurrence rule for an expense, or nil if it does not repeat on a schedule EventKit can
    /// express.
    ///
    /// Day-of-month handling is the one wrinkle. Left to itself, a monthly rule anchored on the 31st
    /// simply skips the months that have no 31st — February would never produce an occurrence. The
    /// app clamps such a bill to the last day of the month (`CalendarDate.clamping`), so the rule
    /// says the same thing with `daysOfTheMonth: [-1]`.
    static func recurrenceRule(for expense: Expense) -> EKRecurrenceRule {
        switch expense.frequency.recurrenceInterval {
        case .weeks(let interval):
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: interval, end: nil)

        case .months(let interval):
            let lastDayOfMonth = expense.dueDay >= 29
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: interval,
                daysOfTheWeek: nil,
                daysOfTheMonth: lastDayOfMonth ? [-1] : nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil)
        }
    }

    /// How far ahead of the due date to warn, matching what the dashboard calls "due soon".
    ///
    /// Used by the calendar event only. Reminders conflates an alarm with the item's date, so a
    /// reminder carries none — see `ReminderExport.apply`.
    static func alarmOffset(for expense: Expense) -> TimeInterval {
        -Double(expense.frequency.dueSoonThresholdDays) * 24 * 60 * 60
    }
}
