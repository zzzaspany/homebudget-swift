import Charts
import HomeBudgetCore
import SwiftUI

/// What a bill has cost over time, and how far it has drifted.
///
/// Most useful for the variable ones — electricity and gas move enough that the trend is the point,
/// not the individual amounts.
struct PriceHistoryContent: View {
    let expense: Expense
    let session: AutheliaSession

    @State private var history: PriceHistory?
    @State private var errorMessage: String?

    private var language: Language { .device }

    var body: some View {
        Group {
            if let history, !history.entries.isEmpty {
                content(history)
            } else if let errorMessage {
                ContentUnavailableView(
                    UIString.loadFailed(language), systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage))
            } else if history != nil {
                ContentUnavailableView(
                    UIString.emptyPayments(language), systemImage: "tray")
            } else {
                ProgressView()
            }
        }
        // Keyed on the expense so switching rows in the iPad's detail column reloads, rather than
        // leaving the previous bill's chart under the new bill's title.
        .task(id: expense.id) { await load() }
    }

    private func content(_ history: PriceHistory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                drift(history)
                chart(history)
                table(history)
            }
            .padding()
        }
    }

    private func drift(_ history: PriceHistory) -> some View {
        let change = history.priceChangePercent
        let colour: Color = change > 0 ? .red : (change < 0 ? .green : .secondary)

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(change > 0 ? "+" : "")\(NumberFormatting.trimmed(change, language: language))%")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(colour)
                .contentTransition(.numericText())

            Text(language == .pl
                ? "od pierwszej wpłaty"
                : "since the first payment")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(colour.opacity(0.12)), in: .rect(cornerRadius: 20))
    }

    private func chart(_ history: PriceHistory) -> some View {
        // The axis is bounded to the payments themselves, with a little room either side. Left to
        // its own devices the chart starts at zero, and a 30% rise on a utility bill flattens into
        // a gentle slope — which is the one thing this screen exists to show. The area has to be
        // anchored to that lower bound explicitly, since otherwise it drags the baseline back to
        // zero and takes the scale with it.
        let amounts = history.entries.map(\.amountPaid)
        let lowest = (amounts.min() ?? 0)
        let highest = (amounts.max() ?? 0)
        let padding = max((highest - lowest) * 0.25, highest * 0.05, 1)
        let floor = max(lowest - padding, 0)
        let ceiling = highest + padding

        return Chart(history.entries, id: \.datePaid) { entry in
            LineMark(
                x: .value(UIString.columnPeriod(language),
                          Localization.periodLabel(entry.period, language: language)),
                y: .value(UIString.columnAmount(language), entry.amountPaid)
            )
            .interpolationMethod(.monotone)
            .symbol(.circle)

            AreaMark(
                x: .value(UIString.columnPeriod(language),
                          Localization.periodLabel(entry.period, language: language)),
                yStart: .value(UIString.columnAmount(language), floor),
                yEnd: .value(UIString.columnAmount(language), entry.amountPaid)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [.accentColor.opacity(0.35), .clear],
                startPoint: .top, endPoint: .bottom))
        }
        .chartYScale(domain: floor...ceiling)
        .frame(height: 220)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func table(_ history: PriceHistory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(UIString.sectionPaymentHistory(language))
                .font(.headline)

            ForEach(history.entries.reversed(), id: \.datePaid) { entry in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localization.periodLabel(entry.period, language: language))
                        Text(Localization.dateLabel(entry.datePaid, language: language))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(NumberFormatting.currency(entry.amountPaid, language: language))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
    }

    private func load() async {
        #if DEBUG
            if DevelopMode.isOn {
                history = DevelopMode.priceHistory(expenseID: expense.id)
                return
            }
        #endif

        do {
            history = try await APIClient(session: session).history(expenseID: expense.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The sheet the phone presents, wrapping the same content in its own navigation container.
///
/// On iPad the content goes into the split view's detail column instead, which supplies the title
/// and needs no dismiss button — hence the split.
struct PriceHistoryScreen: View {
    let expense: Expense
    let session: AutheliaSession

    @Environment(\.dismiss) private var dismiss
    private var language: Language { .device }

    var body: some View {
        NavigationStack {
            PriceHistoryContent(expense: expense, session: session)
                .navigationTitle(expense.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(UIString.actionCancel(language)) { dismiss() }
                    }
                }
        }
    }
}
