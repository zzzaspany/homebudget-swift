import Foundation
import HomeBudgetCore
import UserNotifications

/// Local notifications warning that a bill is about to fall due.
///
/// Local, not push: the schedule is known days in advance and nothing about it needs a server. A
/// push pipeline would mean APNs certificates, a device-token store and a sender in the Vapor app,
/// all to deliver something the phone can work out for itself from data it already has.
///
/// Everything is rescheduled from scratch on each refresh rather than diffed. There are at most a
/// few dozen, the source of truth is the dashboard, and reconciling two sets of pending
/// notifications is more code and more ways to be wrong than simply replacing them.
@MainActor
enum DueNotifications {
    /// Well under the 64 pending notifications iOS keeps per app, past which it silently drops the
    /// rest. Leaves room for anything else the app might schedule later.
    private static let limit = 32
    private static let prefix = "due."

    /// Asks once. A refusal is remembered by the system, so asking again on every launch would only
    /// annoy — the request returns false immediately from then on.
    static func requestAuthorization() async -> Bool {
        let centre = UNUserNotificationCenter.current()
        let settings = await centre.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    /// Replaces every scheduled warning with one derived from this dashboard, and reports how many
    /// the system is actually holding afterwards.
    ///
    /// The count is read back from `pendingNotificationRequests` rather than counted as we go. Those
    /// are different numbers: `add` can reject a request, and a caller that reports what it *meant*
    /// to schedule would happily say "6" while the system held none.
    ///
    /// Silently does nothing when notifications are not authorised: this runs on every dashboard
    /// refresh, and a refresh is not the moment to interrupt somebody with a permission prompt.
    @discardableResult
    static func reschedule(from dashboard: Dashboard, language: Language) async -> Int {
        let centre = UNUserNotificationCenter.current()
        guard await centre.notificationSettings().authorizationStatus == .authorized else { return 0 }

        let pending = await centre.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        centre.removePendingNotificationRequests(withIdentifiers: pending)

        for reminder in dashboard.dueReminders(after: CalendarDate.today(), limit: limit) {
            let content = UNMutableNotificationContent()
            content.title = reminder.name
            content.body = body(for: reminder, language: language)
            content.sound = .default
            content.threadIdentifier = "homebudget.due"

            // Morning of the warning day, matching the hour the Reminders export uses, so the two
            // integrations do not arrive at contradictory times of day.
            var components = DateComponents()
            components.year = reminder.fireDate.year
            components.month = reminder.fireDate.month
            components.day = reminder.fireDate.day
            components.hour = EventKitBridge.dueHour

            let request = UNNotificationRequest(
                identifier: "\(prefix)\(reminder.expenseID)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
            try? await centre.add(request)
        }

        return await centre.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(prefix) }
            .count
    }

    /// Cancels everything this app scheduled — used when signing out, so a device that no longer
    /// has a session stops announcing somebody else's bills.
    static func cancelAll() async {
        let centre = UNUserNotificationCenter.current()
        let pending = await centre.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
        centre.removePendingNotificationRequests(withIdentifiers: pending)
    }

    private static func body(for reminder: DueReminder, language: Language) -> String {
        let amount = NumberFormatting.currency(reminder.amount, language: language)
        let date = Localization.dateLabel(reminder.dueDate, language: language)
        let days = reminder.daysBefore

        if language == .pl {
            // Polish counts in three forms; "dni" covers everything but the 2-4 group.
            let last = days % 10
            let lastTwo = days % 100
            let few = (2...4).contains(last) && !(12...14).contains(lastTwo)
            let word = days == 1 ? "dzień" : (few ? "dni" : "dni")
            return "\(amount) — termin \(date), za \(days) \(word)."
        }
        return "\(amount) — due \(date), in \(days) \(days == 1 ? "day" : "days")."
    }
}
