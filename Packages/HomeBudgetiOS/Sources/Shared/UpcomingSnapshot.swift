import Foundation
import HomeBudgetCore

/// What the widget draws, written by the app and read by the extension.
///
/// The widget does not call the API. It would need the Authelia cookie, a network round trip and
/// its own failure handling, all inside a process the system gives a few seconds and little memory.
/// The app already fetches this data; it hands over a small snapshot instead.
struct UpcomingSnapshot: Codable, Hashable {
    struct Entry: Codable, Hashable, Identifiable {
        let id: String
        let name: String
        let amount: Double
        let dueDate: CalendarDate
        let daysLeft: Int
        let status: ExpenseStatus
    }

    let entries: [Entry]
    /// When the app last wrote this, so the widget can say the figures are stale rather than
    /// quietly showing something from last week.
    let capturedOn: CalendarDate

    static let empty = UpcomingSnapshot(entries: [], capturedOn: CalendarDate.today())
}

/// The container both the app and the widget read.
///
/// An app group, because a widget runs in its own process and cannot see the app's own defaults.
/// Falling back to `.standard` keeps the app working if the group is unavailable — the widget then
/// shows nothing, which is better than the app crashing over a missing entitlement.
enum SharedStore {
    static let appGroup = "group.lab.office.homebudget"
    static let snapshotKey = "upcomingSnapshot"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func write(_ snapshot: UpcomingSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func read() -> UpcomingSnapshot {
        guard let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(UpcomingSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}

extension UpcomingSnapshot {
    /// The soonest bills still to be paid, nearest first.
    ///
    /// Paid and inactive ones are left out: a widget the size of a stamp should answer "what is
    /// coming" and nothing else.
    static func from(_ dashboard: Dashboard, limit: Int = 4) -> UpcomingSnapshot {
        let entries = dashboard.upcoming(limit: limit).compactMap { summary -> Entry? in
            guard let due = summary.dueDate, let daysLeft = summary.daysLeft else { return nil }
            return Entry(
                id: summary.expense.id, name: summary.expense.name,
                amount: summary.expense.amount, dueDate: due, daysLeft: daysLeft,
                status: summary.status)
        }
        return UpcomingSnapshot(entries: entries, capturedOn: CalendarDate.today())
    }
}
