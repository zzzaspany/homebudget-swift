import Charts
import HomeBudgetCore
import SwiftUI

/// What a bill has cost over time, and how far it has drifted.
///
/// Most useful for the variable ones — electricity and gas move enough that the trend is the point,
/// not the individual amounts.
struct PriceHistoryScreen: View {
    let expense: Expense
    let session: AutheliaSession

    @State private var history: PriceHistory?
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    private var language: Language { .device }

    var body: some View {
        NavigationStack {
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
            .navigationTitle(expense.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(UIString.actionCancel(language)) { dismiss() }
                }
            }
            .task { await load() }
        }
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
            Text("\(change > 0 ? "+" : "")\(NumberFormatting.plain(change))%")
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
        Chart(history.entries, id: \.datePaid) { entry in
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
                y: .value(UIString.columnAmount(language), entry.amountPaid)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(.linearGradient(
                colors: [.accentColor.opacity(0.35), .clear],
                startPoint: .top, endPoint: .bottom))
        }
        // The axis starts at the lowest payment rather than zero, so a small drift is still visible.
        .chartYScale(domain: .automatic(includesZero: false))
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
