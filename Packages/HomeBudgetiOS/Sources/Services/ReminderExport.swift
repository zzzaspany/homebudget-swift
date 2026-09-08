import EventKit
import Foundation
import HomeBudgetCore
import Observation

/// Mirrors the recurring expenses into Apple Reminders, on a list of their own.
///
/// Reminders rather than calendar events because a bill is a task: it has a due date, it gets ticked
/// off, and it belongs in Today alongside everything else that needs doing. A calendar event would
/// say "this is happening" when what is meant is "you have to do this".
///
/// The list is created and owned by this app. Deleting it in Reminders removes everything at once,
/// and the next export recreates it — so there is no state here the user cannot get rid of.
@MainActor
@Observable
final class ReminderExport {
    enum Outcome: Equatable {
        case added(Int)
        case updated(Int)
        case denied
        case failed(String)
    }

    private(set) var lastOutcome: Outcome?
    private(set) var isExporting = false

    /// Maps an expense to the reminder created for it, so a second export updates rather than
    /// duplicates.
    ///
    /// Local to the device on purpose: an `EKReminder` identifier means nothing on another phone, so
    /// there is nothing here worth putting on the server.
    private let identifiersKey = "reminderIdentifiers"
    private let listKey = "reminderListIdentifier"
    private let lastSyncKey = "reminderLastSyncDate"

    private var identifiers: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: identifiersKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: identifiersKey) }
    }

    /// Whether the export has been used, which is what decides if the menu offers to re-run it.
    var hasExported: Bool { !identifiers.isEmpty }

    /// Dismisses the result of the last export.
    func acknowledge() { lastOutcome = nil }

    func export(_ summaries: [Dashboard.ExpenseSummary], listName: String) async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        guard await requestAccess() else {
            lastOutcome = .denied
            return
        }

        do {
            let calendar = try reminderList(named: listName)
            var known = identifiers
            var added = 0
            var updated = 0

            for summary in summaries where summary.expense.active {
                guard let due = summary.dueDate else { continue }

                let existing = known[summary.expense.id]
                    .flatMap { EventKitBridge.store.calendarItem(withIdentifier: $0) as? EKReminder }

                let reminder = existing ?? EKReminder(eventStore: EventKitBridge.store)
                if existing == nil { added += 1 } else { updated += 1 }

                apply(summary, due: due, to: reminder, in: calendar)
                try EventKitBridge.store.save(reminder, commit: false)
                known[summary.expense.id] = reminder.calendarItemIdentifier
            }

            try EventKitBridge.store.commit()
            identifiers = known
            lastOutcome = added > 0 ? .added(added) : .updated(updated)
        } catch {
            lastOutcome = .failed(error.localizedDescription)
        }
    }

    /// Removes everything this app put in Reminders, and forgets the mapping.
    func removeAll() async {
        guard await requestAccess() else {
            lastOutcome = .denied
            return
        }

        do {
            for identifier in identifiers.values {
                if let reminder = EventKitBridge.store.calendarItem(withIdentifier: identifier)
                    as? EKReminder
                {
                    try EventKitBridge.store.remove(reminder, commit: false)
                }
            }
            try EventKitBridge.store.commit()
            identifiers = [:]
            UserDefaults.standard.removeObject(forKey: listKey)
            lastOutcome = .updated(0)
        } catch {
            lastOutcome = .failed(error.localizedDescription)
        }
    }

    /// Expense identifiers whose reminder has been ticked off since the last time this was asked.
    ///
    /// This is what full access to Reminders was taken for. A recurring reminder that is completed
    /// spawns its next occurrence, so "completed" is a moment rather than a state — the completion
    /// date is compared against a high-water mark instead of the flag being trusted on its own.
    func completedSinceLastSync() async -> [String] {
        guard await requestAccess() else {
            lastOutcome = .denied
            return []
        }

        let since = UserDefaults.standard.object(forKey: lastSyncKey) as? Date ?? .distantPast
        let known = identifiers
        var paid: [String] = []
        var newest = since

        for (expenseID, identifier) in known {
            guard
                let reminder = EventKitBridge.store.calendarItem(withIdentifier: identifier)
                    as? EKReminder,
                let completed = reminder.completionDate
            else { continue }

            if completed > since {
                paid.append(expenseID)
                newest = max(newest, completed)
            }
        }

        // Only moved when something was found, so a sync that finds nothing cannot swallow a
        // completion that lands a moment later.
        if !paid.isEmpty {
            UserDefaults.standard.set(newest, forKey: lastSyncKey)
        }
        return paid
    }

    // MARK: - Details

    /// Reminders has no write-only access level the way Calendar does — it is full access or
    /// nothing. That is the price of being able to read completions back later.
    private func requestAccess() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            return true
        case .denied, .restricted, .writeOnly:
            return false
        default:
            return (try? await EventKitBridge.store.requestFullAccessToReminders()) ?? false
        }
    }

    private func apply(
        _ summary: Dashboard.ExpenseSummary, due: CalendarDate, to reminder: EKReminder,
        in calendar: EKCalendar
    ) {
        let expense = summary.expense
        let language = Language.device

        reminder.calendar = calendar
        reminder.title = "\(expense.name) — \(NumberFormatting.currency(expense.amount, language: language))"
        reminder.notes = Localization.category(expense.category, language: language)
        reminder.dueDateComponents = EventKitBridge.dueComponents(due)
        reminder.recurrenceRules = [EventKitBridge.recurrenceRule(for: expense)]

        // No alarm of our own, deliberately. Reminders treats an item's alarm as its date — set one
        // `dueSoonThresholdDays` early and the bill *displays* as due that many days before it
        // really is, and the recurrence rule anchors on the wrong day of the month with it. A
        // monthly bill due on the 5th came out as "every month that has 31 days", which would skip
        // February outright.
        //
        // So the date shown is the date the money is due, and the early warning stays where it
        // already worked: the dashboard's own alerts and the e-mail notifications.
        reminder.alarms?.forEach(reminder.removeAlarm)
    }

    /// The app's own list, found by the identifier we stored or created fresh.
    private func reminderList(named name: String) throws -> EKCalendar {
        if let identifier = UserDefaults.standard.string(forKey: listKey),
            let existing = EventKitBridge.store.calendar(withIdentifier: identifier)
        {
            return existing
        }

        let calendar = EKCalendar(for: .reminder, eventStore: EventKitBridge.store)
        calendar.title = name

        // Follow whatever account the user already keeps reminders in, so these sync the same way
        // the rest do. Falling back to a local source keeps this working on a device with no iCloud.
        calendar.source =
            EventKitBridge.store.defaultCalendarForNewReminders()?.source
            ?? EventKitBridge.store.sources.first { $0.sourceType == .local }
            ?? EventKitBridge.store.sources.first

        try EventKitBridge.store.saveCalendar(calendar, commit: true)
        UserDefaults.standard.set(calendar.calendarIdentifier, forKey: listKey)
        return calendar
    }
}
