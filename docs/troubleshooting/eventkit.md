# Reminders and Calendar (EventKit)

The iOS app mirrors recurring expenses into Apple Reminders, and offers a per-expense "Add to
Calendar" through Apple's own event editor. See `Packages/HomeBudgetiOS/Sources/Services/`.

## Every reminder showed up several days before it was due

**Symptom.** After the first export, every bill in Reminders carried the wrong date — always exactly
`dueSoonThresholdDays` early. A monthly bill due on the 18th showed as due on the 13th; a quarterly
one due on the 10th showed as the 3rd. Worse, one monthly bill's recurrence read **"Every month that
has 31 days"**, which would have skipped February entirely.

**Cause.** `dueDateComponents` was correct. The alarm was not — or rather, Reminders does not
separate the two. **A reminder's alarm *is* the date Reminders displays and schedules it on.** An
early-warning alarm set `dueSoonThresholdDays` before the due date therefore moves the item itself,
and the recurrence rule then anchors on the moved day of the month. A bill due on the 5th, warned 5
days early, landed on the 31st of the previous month, and the rule followed it there.

Switching the alarm from `EKAlarm(absoluteDate:)` to `EKAlarm(relativeOffset:)` did **not** fix it —
the offset is still resolved against the due date, and the resulting instant is still what Reminders
shows.

**Fix.** No alarm of our own on an `EKReminder`. The item carries the real due date and nothing else,
so the date on screen is the date the money is due and the recurrence anchors on the right day. The
early warning already exists elsewhere — the dashboard's alerts and the e-mail notifications — and
Reminders has its own "Early Reminder" setting for anyone who wants one.

Calendar events are unaffected: `EKEvent` keeps its alarm and its date separate, so the per-expense
event does carry an `EKAlarm(relativeOffset:)` at `-dueSoonThresholdDays`, which the system editor
displays as "14 days before" for a yearly bill.

*Hit 2026-09-08.*

## A reminder due date needs a time

**Symptom.** Related to the above, and worth stating separately: `dueDateComponents` with only
year/month/day makes the reminder undated-with-a-day, and EventKit then leans on the alarm for the
actual schedule.

**Fix.** `EventKitBridge.dueComponents` sets an hour (09:00). Nothing in the domain has a time of
day, so one is chosen — morning, when there is still a working day left to pay the bill in.

## Completing a recurring reminder does not complete the reminder you created

**Symptom.** The read-back found nothing. Tick a bill off in Reminders, return to the app, and no
completion is detected — while the log shows the app did query ReminderKit and got an answer.

**Cause.** Completing a *recurring* reminder advances the series: the item at the identifier you
stored is still open, with its due date moved to the next occurrence. The occurrence you ticked off
is preserved as a **separate item**, with its own identifier, which appears under Completed. So
looking up your stored identifiers and checking `completionDate` can never succeed — those items are
by definition the ones still outstanding.

Observed directly: after ticking off "Prąd" on 9 September, the series showed `10/10/2026` in the
HomeBudget list while a separate entry sat under Completed reading `Completed: Today, 07:07`.

**Fix.** Ask the store what was completed, rather than inspecting what you created:

```swift
let predicate = store.predicateForCompletedReminders(
    withCompletionDateStarting: since, ending: nil, calendars: [list])
```

That returns items you did not create and cannot match by identifier, so each reminder carries its
expense in `EKCalendarItem.url` (`homebudget://expense/<id>`) — a field the user never sees and
completion does not discard. Matching on the title would break the moment an amount changed, because
the title contains it.

`EKReminder` is not `Sendable`, so the identifier and completion date have to be extracted inside
the fetch callback rather than letting the objects cross an isolation boundary.

*Hit 2026-09-09.*

## Permission levels are not symmetrical

Worth knowing before designing a feature around either:

| | Levels available | Info.plist key |
| --- | --- | --- |
| Reminders | **Full access only** — there is no write-only tier | `NSRemindersFullAccessUsageDescription` |
| Calendar | Write-only (iOS 17+) or full | `NSCalendarsWriteOnlyAccessUsageDescription` |

That asymmetry drove the design. Reminders is the primary target and takes full access, which is
what will later allow reading completions back to register a payment. Calendar is written to one
event at a time through `EKEventEditViewController`, which needs only write-only — iOS shows a
visibly milder prompt ("would like to **add to** your Calendar") and the app never sees the user's
diary.

`EKReminder` has no system editor: there is no `EKReminderEditViewController` to match
`EKEventEditViewController`. A reminder is written silently or behind your own sheet.

## Day-of-month clamping

A monthly rule anchored on the 31st skips every month that has no 31st. The app clamps such a bill to
the last day of the month (`CalendarDate.clamping`), so the recurrence has to say the same thing:
`daysOfTheMonth: [-1]` for any expense with `dueDay >= 29`. See `EventKitBridge.recurrenceRule`.

## Avoiding duplicates

`expenseID → calendarItemIdentifier` in `UserDefaults`, and a re-export updates in place. Kept on the
device rather than the server on purpose: an EventKit identifier means nothing on another phone, so
there is nothing there worth syncing. Verified — a second export left the list at 12 items and
reported "Reminders updated" rather than "Added".
