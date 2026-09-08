import Charts
import HomeBudgetCore
import SwiftUI

/// Where the money goes, and what the next twelve months look like.
///
/// Swift Charts rather than the hand-drawn SVG the web client needs: on this platform the framework
/// is there, and it brings selection, accessibility and animation for free.
struct ChartsScreen: View {
    let model: DashboardModel

    private var language: Language { .device }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let dashboard = model.dashboard {
                        categoryBreakdown(dashboard.categoryBreakdown)
                        projection(dashboard.projection)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                    }
                }
                .padding()
            }
            .navigationTitle(UIString.viewCharts(language))
            .refreshable { await model.load() }
        }
    }

    // MARK: - Categories

    @ViewBuilder
    private func categoryBreakdown(_ shares: [Dashboard.CategoryShare]) -> some View {
        let total = shares.reduce(0) { $0 + $1.proratedAmount }

        VStack(alignment: .leading, spacing: 12) {
            Text(UIString.sectionCategoryChart(language))
                .font(.headline)

            if shares.isEmpty {
                Text(UIString.emptyExpenses(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Chart(shares, id: \.category) { share in
                    SectorMark(
                        angle: .value(UIString.columnAmount(language), share.proratedAmount),
                        innerRadius: .ratio(0.62),
                        angularInset: 1.5
                    )
                    .cornerRadius(4)
                    .foregroundStyle(by: .value(
                        UIString.columnCategory(language),
                        Localization.category(share.category, language: language)))
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(height: 280)
                // The total belongs in the hole, where it reads as the sum of what surrounds it.
                .chartBackground { proxy in
                    GeometryReader { geometry in
                        if let plot = proxy.plotFrame {
                            let frame = geometry[plot]
                            VStack(spacing: 2) {
                                Text(UIString.kpiMonthlyBudget(language))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(NumberFormatting.currency(total, language: language))
                                    .font(.title3.bold())
                            }
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
                .padding(16)
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
    }

    // MARK: - Projection

    @ViewBuilder
    private func projection(_ entries: [Dashboard.ProjectionEntry]) -> some View {
        let peak = entries.map(\.amount).max() ?? 0

        VStack(alignment: .leading, spacing: 12) {
            Text(UIString.sectionProjection(language))
                .font(.headline)

            Chart(entries, id: \.self) { entry in
                BarMark(
                    x: .value(
                        UIString.columnPeriod(language),
                        Localization.monthAbbreviation(entry.month, language: language)),
                    y: .value(UIString.columnAmount(language), entry.amount)
                )
                .foregroundStyle(entry.amount >= peak ? Color.orange : Color.accentColor)
                .cornerRadius(5)
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(NumberFormatting.compact(amount, language: language))
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))

            Text("\(UIString.chartPeak(language)): \(NumberFormatting.currency(peak, language: language))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension Language {
    /// The device's language, falling back to Polish for anything the app does not translate.
    static var device: Language {
        Language(code: Locale.current.language.languageCode?.identifier)
    }
}
