import HomeBudgetCore
import SwiftUI

/// The month, with what falls due on each day.
///
/// The layout comes from `MonthGrid` in the shared core, so this screen and the web client agree on
/// which bills land on which date — the Python app kept that rule in two places and they drifted.
struct CalendarScreen: View {
    let model: DashboardModel
    @State private var year = CalendarDate.today().year
    @State private var month = CalendarDate.today().month
    @State private var selected: MonthGrid.Day?

    private var language: Language { .device }

    private var weekdays: [String] {
        language == .pl
            ? ["Pon", "Wt", "Śr", "Czw", "Pt", "Sob", "Nie"]
            : ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    }

    private var grid: MonthGrid {
        MonthGrid.build(
            year: year, month: month,
            expenses: model.dashboard?.expenses.map(\.expense) ?? [],
            today: .today())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    monthHeader
                    weekdayHeader
                    days
                    if let selected, !selected.entries.isEmpty {
                        dayDetail(selected)
                    }
                }
                .padding()
            }
            .navigationTitle(UIString.viewCalendar(language))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(language == .pl ? "Dziś" : "Today") {
                        let today = CalendarDate.today()
                        withAnimation { year = today.year; month = today.month }
                    }
                }
            }
        }
    }

    private var monthHeader: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.glass)

            Spacer()
            Text("\(Localization.monthName(month, language: language)) \(String(year))")
                .font(.title3.weight(.semibold))
                .contentTransition(.numericText())
            Spacer()

            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.glass)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(weekdays, id: \.self) { day in
                Text(day)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var days: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(0..<grid.leadingBlanks, id: \.self) { _ in
                Color.clear.frame(height: 62)
            }
            ForEach(grid.days, id: \.date) { day in
                dayCell(day)
                    .onTapGesture {
                        withAnimation(.snappy) {
                            selected = selected?.date == day.date ? nil : day
                        }
                    }
            }
        }
    }

    private func dayCell(_ day: MonthGrid.Day) -> some View {
        VStack(spacing: 3) {
            Text("\(day.date.day)")
                .font(.caption.weight(day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? Color.accentColor : .primary)

            // Bills are dots rather than labels: at this size a name is unreadable, and the count
            // and urgency are what the month view is for.
            HStack(spacing: 3) {
                ForEach(day.entries.prefix(3), id: \.id) { entry in
                    Circle()
                        .fill(color(for: entry.status))
                        .frame(width: 5, height: 5)
                }
                if day.entries.count > 3 {
                    Text("+\(day.entries.count - 3)")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .glassEffect(
            .regular.tint(day.isToday ? Color.accentColor.opacity(0.2) : nil),
            in: .rect(cornerRadius: 12))
        .overlay {
            if selected?.date == day.date {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
    }

    private func dayDetail(_ day: MonthGrid.Day) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Localization.dateLabel(day.date, language: language))
                .font(.headline)

            ForEach(day.entries, id: \.id) { entry in
                HStack {
                    Circle().fill(color(for: entry.status)).frame(width: 8, height: 8)
                    Text(entry.name)
                    Spacer()
                    Text(NumberFormatting.currency(entry.amount, language: language))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func color(for status: ExpenseStatus) -> Color {
        switch status {
        case .overdue: .red
        case .dueSoon: .orange
        case .paid: .green
        case .upcoming: .accentColor
        case .inactive: .secondary
        }
    }

    private func step(_ offset: Int) {
        let absolute = (year * 12 + month - 1) + offset
        withAnimation(.snappy) {
            year = absolute / 12
            month = absolute % 12 + 1
            selected = nil
        }
    }
}
