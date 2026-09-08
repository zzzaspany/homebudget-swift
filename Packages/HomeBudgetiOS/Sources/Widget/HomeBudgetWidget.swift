import HomeBudgetCore
import SwiftUI
import WidgetKit

/// The next bills due, and how many days are left on each.
///
/// Reads the snapshot the app leaves in the shared container rather than calling the API — see
/// `UpcomingSnapshot`.
struct UpcomingProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpcomingEntry {
        UpcomingEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (UpcomingEntry) -> Void) {
        // The gallery preview gets sample data; a real placement gets whatever the app last wrote.
        let snapshot = context.isPreview ? .sample : SharedStore.read()
        completion(UpcomingEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpcomingEntry>) -> Void) {
        let snapshot = SharedStore.read()
        // Refreshed just after the next midnight: "days left" is the only thing that changes on its
        // own, and it changes exactly once a day. Waking more often would spend the system's
        // refresh budget for nothing.
        let tomorrow =
            Calendar.current.nextDate(
                after: Date(), matching: DateComponents(hour: 0, minute: 1),
                matchingPolicy: .nextTime) ?? Date().addingTimeInterval(3600)

        completion(
            Timeline(
                entries: [UpcomingEntry(date: Date(), snapshot: snapshot)],
                policy: .after(tomorrow)))
    }
}

struct UpcomingEntry: TimelineEntry {
    let date: Date
    let snapshot: UpcomingSnapshot
}

extension UpcomingSnapshot {
    /// Shown in the widget gallery, where there is no real data yet.
    static let sample = UpcomingSnapshot(
        entries: [
            Entry(
                id: "1", name: "Prąd", amount: 245.50,
                dueDate: CalendarDate.today().addingDays(2), daysLeft: 2, status: .dueSoon),
            Entry(
                id: "2", name: "Abonament telefon", amount: 65,
                dueDate: CalendarDate.today().addingDays(4), daysLeft: 4, status: .dueSoon),
            Entry(
                id: "3", name: "Podatek od nieruchomości", amount: 320,
                dueDate: CalendarDate.today().addingDays(7), daysLeft: 7, status: .upcoming),
        ],
        capturedOn: CalendarDate.today())
}

struct UpcomingWidgetView: View {
    let entry: UpcomingEntry
    @Environment(\.widgetFamily) private var family

    private var language: Language { .device }

    /// One bill on the small tile, three on the medium one. A small widget that tries to show a
    /// list ends up showing three unreadable lines.
    private var shown: [UpcomingSnapshot.Entry] {
        Array(entry.snapshot.entries.prefix(family == .systemSmall ? 1 : 3))
    }

    var body: some View {
        if shown.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text(UIString.emptyAlerts(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } else if family == .systemSmall {
            small(shown[0])
        } else {
            medium
        }
    }

    // MARK: - Small

    private func small(_ item: UpcomingSnapshot.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(countdown(item.daysLeft))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(tint(item.status))
                .contentTransition(.numericText())

            Text(daysWord(item.daysLeft))
                .font(.caption2)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(NumberFormatting.currency(item.amount, language: language))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Medium

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shown) { item in
                HStack(spacing: 10) {
                    Circle()
                        .fill(tint(item.status))
                        .frame(width: 7, height: 7)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(Localization.dateLabel(item.dueDate, language: language))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(NumberFormatting.currency(item.amount, language: language))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Text("\(countdown(item.daysLeft)) \(daysWord(item.daysLeft))")
                            .font(.caption2)
                            .foregroundStyle(tint(item.status))
                    }
                    .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Wording

    /// Negative days mean the bill is already late, and the widget says so rather than showing a
    /// minus sign nobody would parse at a glance.
    private func countdown(_ days: Int) -> String {
        days < 0 ? "\(-days)" : "\(days)"
    }

    private func daysWord(_ days: Int) -> String {
        let count = abs(days)
        if days < 0 {
            return language == .pl ? "dni po terminie" : (count == 1 ? "day late" : "days late")
        }
        if days == 0 { return language == .pl ? "dziś" : "today" }
        if language == .en { return count == 1 ? "day left" : "days left" }

        // Polish counts in three forms; "dni" covers everything except the 2-4 group.
        let last = count % 10
        let lastTwo = count % 100
        let few = (2...4).contains(last) && !(12...14).contains(lastTwo)
        return few ? "dni zostały" : "dni zostało"
    }

    private func tint(_ status: ExpenseStatus) -> Color {
        switch status {
        case .overdue: .red
        case .dueSoon: .orange
        case .upcoming: .accentColor
        default: .secondary
        }
    }
}

struct UpcomingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingExpenses", provider: UpcomingProvider()) { entry in
            UpcomingWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("HomeBudget")
        .description(
            Language.device == .pl
                ? "Najbliższe terminy płatności i ile dni zostało."
                : "The next bills due, and how many days are left.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct HomeBudgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpcomingWidget()
    }
}
