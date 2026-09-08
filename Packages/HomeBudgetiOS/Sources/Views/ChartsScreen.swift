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
                    .foregroundStyle(Color.chartPalette[
                        (shares.firstIndex { $0.category == share.category } ?? 0)
                            % Color.chartPalette.count])
                }
                .chartLegend(.hidden)
                .frame(height: 240)
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

                legend(shares, total: total)
            }
        }
    }

    /// Wraps, and carries the amount beside each name — the built-in legend clips long category
    /// names onto one row and says nothing about how much each is worth.
    private func legend(_ shares: [Dashboard.CategoryShare], total: Double) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(shares.enumerated()), id: \.element.category) { index, share in
                HStack(spacing: 10) {
                    Circle()
                        .fill(Color.chartPalette[index % Color.chartPalette.count])
                        .frame(width: 10, height: 10)

                    Text(Localization.category(share.category, language: language))
                        .font(.subheadline)
                        .lineLimit(2)

                    Spacer(minLength: 8)

                    Text(NumberFormatting.currency(share.proratedAmount, language: language))
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()

                    Text(percentage(share.proratedAmount, of: total))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private func percentage(_ value: Double, of total: Double) -> String {
        guard total > 0 else { return "" }
        return "\(Int((value / total * 100).rounded()))%"
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

extension Color {
    /// The palette the web client uses, so a category is the same colour in both.
    static let chartPalette: [Color] = [
        Color(red: 0.39, green: 0.40, blue: 0.945),
        Color(red: 0.02, green: 0.71, blue: 0.83),
        Color(red: 0.06, green: 0.72, blue: 0.51),
        Color(red: 0.96, green: 0.62, blue: 0.04),
        Color(red: 0.94, green: 0.27, blue: 0.27),
        Color(red: 0.23, green: 0.51, blue: 0.96),
        Color(red: 0.93, green: 0.28, blue: 0.60),
        Color(red: 0.55, green: 0.36, blue: 0.96),
    ]
}

