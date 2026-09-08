import HomeBudgetCore
import SwiftUI

/// What has to be set aside each month for the bills that are not paid monthly.
///
/// The figure people forget: a yearly insurance premium costs nothing in eleven months and a great
/// deal in the twelfth, and only the monthly share makes it comparable to the rent.
struct SinkingFundsScreen: View {
    let dashboard: Dashboard

    private var language: Language { .device }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(UIString.kpiSinkingFund(language))
                        .font(.body.weight(.medium))
                    Spacer()
                    Text(NumberFormatting.currency(
                        dashboard.kpis.sinkingFundTotal, language: language))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
            }

            if dashboard.sinkingFundItems.isEmpty {
                Section {
                    Text(UIString.emptySinkingFunds(language))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(dashboard.sinkingFundItems, id: \.name) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.name).font(.body.weight(.medium))
                                Spacer()
                                Text(NumberFormatting.currency(
                                    item.monthlyReserve, language: language))
                                    .font(.callout.weight(.semibold))
                                    .monospacedDigit()
                            }
                            HStack(spacing: 6) {
                                Text(item.frequency.label(language: language))
                                if let due = item.dueDate {
                                    Text("·")
                                    Text(Localization.dateLabel(due, language: language))
                                }
                                Text("·")
                                Text(UIString.monthlyReserve(language))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle(UIString.sectionSinkingFunds(language))
        .navigationBarTitleDisplayMode(.inline)
    }
}
