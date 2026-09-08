import EventKit
import EventKitUI
import HomeBudgetCore
import SwiftUI

/// Apple's own event editor, prefilled with one expense.
///
/// This is the deliberate counterpart to the reminder export. The export is bulk and silent; this is
/// one bill at a time, and the user sees exactly what is about to be written and can change it or
/// back out. It also needs only write-only calendar access, so it does not ask for the run of the
/// user's diary.
struct EventEditSheet: UIViewControllerRepresentable {
    let expense: Expense
    let dueDate: CalendarDate
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = EventKitBridge.store
        controller.event = makeEvent()
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    private func makeEvent() -> EKEvent {
        let event = EKEvent(eventStore: EventKitBridge.store)
        let language = Language.device

        event.title = "\(expense.name) — \(NumberFormatting.currency(expense.amount, language: language))"
        event.notes = Localization.category(expense.category, language: language)
        event.isAllDay = true
        event.calendar = EventKitBridge.store.defaultCalendarForNewEvents

        // An all-day event still needs a start and an end, and EventKit treats the end as inclusive
        // for all-day items — so a one-day event has both set to the same date.
        if let start = EventKitBridge.date(dueDate) {
            event.startDate = start
            event.endDate = start
        }

        event.recurrenceRules = [EventKitBridge.recurrenceRule(for: expense)]
        event.addAlarm(EKAlarm(relativeOffset: EventKitBridge.alarmOffset(for: expense)))
        return event
    }

    @MainActor
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        nonisolated func eventEditViewController(
            _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
        ) {
            let saved = action == .saved
            Task { @MainActor in self.onFinish(saved) }
        }
    }
}

/// Asks for the lighter of the two calendar permissions.
///
/// Write-only is all this needs: the app adds an event and never reads the calendar back. iOS shows
/// a correspondingly milder prompt, and nothing the user already has in their diary is exposed.
@MainActor
enum CalendarAccess {
    static func request() async -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly:
            return true
        case .denied, .restricted:
            return false
        default:
            return (try? await EventKitBridge.store.requestWriteOnlyAccessToEvents()) ?? false
        }
    }
}
