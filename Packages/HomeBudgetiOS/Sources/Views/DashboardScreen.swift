import HomeBudgetCore
import SwiftUI

@MainActor
@Observable
final class DashboardModel {
    var dashboard: Dashboard?
    var payments: [PaymentRecord] = []
    var errorMessage: String?
    var isLoading = false

    let session: AutheliaSession
    private var client: APIClient { APIClient(session: session) }

    init(session: AutheliaSession) {
        self.session = session
    }

    func load() async {
        #if DEBUG
            if DevelopMode.isOn {
                dashboard = DevelopMode.dashboard
                payments = DevelopMode.payments
                return
            }
        #endif

        isLoading = true
        defer { isLoading = false }
        do {
            async let dashboard = client.dashboard()
            async let payments = client.payments()
            self.dashboard = try await dashboard
            self.payments = try await payments
            errorMessage = nil
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pay(_ expense: Expense, amount: Double?) async {
        #if DEBUG
            if DevelopMode.isOn { return }
        #endif

        do {
            try await client.pay(expenseID: expense.id, amount: amount)
            await load()
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct DashboardScreen: View {
    let session: AutheliaSession
    let model: DashboardModel
    @State private var payTarget: Expense?
    @State private var historyTarget: Expense?
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Two columns on a phone, four across an iPad. An adaptive grid packs the cards against the
    /// leading edge at their minimum width instead of spreading them, which left most of an iPad's
    /// width empty and wrapped the amounts onto two lines.
    private var summaryColumns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    private var language: Language { .device }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let dashboard = model.dashboard {
                        summary(dashboard.kpis)
                        alerts(dashboard.notifications)
                        expenses(dashboard.expenses)
                    } else if model.isLoading {
                        ProgressView().padding(.top, 80)
                    }
                }
                .padding()
            }
            .navigationTitle("HomeBudget")
            .refreshable { await model.load() }
            .task {
                if model.dashboard == nil { await model.load() }
                #if DEBUG
                    // Opens the price history straight away, so it can be looked at without
                    // driving the simulator through the taps that normally reach it.
                    if DevelopMode.isOn, DevelopMode.initialSheet == "history" {
                        historyTarget = model.dashboard?.expenses
                            .first { $0.expense.isVariable }?.expense
                    }
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(UIString.actionRefresh(language), systemImage: "arrow.clockwise") {
                            Task { await model.load() }
                        }
                        Button(UIString.actionSignOut(language), systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                            Task { await session.signOut() }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .alert(UIString.errorTitle(language), isPresented: .constant(model.errorMessage != nil)) {
                Button("OK") { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
            .sheet(item: $historyTarget) { expense in
                PriceHistoryScreen(expense: expense, session: session)
            }
            .sheet(item: $payTarget) { expense in
                PaymentSheet(expense: expense, language: language) { amount in
                    payTarget = nil
                    Task { await model.pay(expense, amount: amount) }
                }
            }
        }
    }

    // MARK: - Summary

    /// The figures, on glass.
    ///
    /// A `GlassEffectContainer` groups them so the material is sampled once for the whole set —
    /// separate glass views would each refract independently and the row would look busy.
    private func summary(_ kpis: Dashboard.KPIs) -> some View {
        GlassEffectContainer(spacing: 16) {
            LazyVGrid(columns: summaryColumns, spacing: 16) {
                figure(UIString.kpiMonthlyBudget(language),
                       NumberFormatting.currency(kpis.proRatedMonthly, language: language),
                       tint: .accentColor)
                figure(UIString.kpiSinkingFund(language),
                       NumberFormatting.currency(kpis.sinkingFundTotal, language: language),
                       tint: .teal)
                figure(UIString.kpiMonthlyDues(language),
                       NumberFormatting.currency(kpis.monthlyTotal, language: language))
                figure(UIString.kpiYearlyDues(language),
                       NumberFormatting.currency(kpis.yearlyTotal, language: language))
            }
        }
    }

    private func figure(_ label: String, _ value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular.tint(tint?.opacity(0.18)), in: .rect(cornerRadius: 20))
    }

    // MARK: - Alerts

    @ViewBuilder
    private func alerts(_ notifications: [Dashboard.NotificationItem]) -> some View {
        if !notifications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(UIString.sectionAlerts(language))
                    .font(.headline)

                ForEach(notifications) { item in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(item.status == .overdue ? Color.red : Color.orange)
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body.weight(.medium))
                            Text(Localization.notificationMessage(
                                status: item.status, daysLeft: item.daysLeft, language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(NumberFormatting.currency(item.amount, language: language))
                            .font(.callout.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(14)
                    .glassEffect(
                        .regular.tint((item.status == .overdue ? Color.red : .orange).opacity(0.14)),
                        in: .rect(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Expenses

    private func expenses(_ summaries: [Dashboard.ExpenseSummary]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(UIString.sectionExpenses(language))
                .font(.headline)

            ForEach(summaries) { summary in
                ExpenseRow(
                    summary: summary, language: language,
                    onPay: { payTarget = summary.expense },
                    onHistory: { historyTarget = summary.expense })
            }
        }
    }
}

struct ExpenseRow: View {
    let summary: Dashboard.ExpenseSummary
    let language: Language
    let onPay: () -> Void
    let onHistory: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.expense.name).font(.body.weight(.medium))
                HStack(spacing: 6) {
                    Text(Localization.category(summary.expense.category, language: language))
                    if let due = summary.dueDate {
                        Text("·")
                        Text(Localization.dateLabel(due, language: language))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(NumberFormatting.currency(summary.expense.amount, language: language))
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                StatusBadge(status: summary.status, language: language)
            }

            Button(action: onPay) {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.glass)
            .accessibilityLabel(UIString.actionPay(language))
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
        .onTapGesture(perform: onHistory)
    }
}

struct StatusBadge: View {
    let status: ExpenseStatus
    let language: Language

    private var color: Color {
        switch status {
        case .overdue: .red
        case .dueSoon: .orange
        case .paid: .green
        case .upcoming: .accentColor
        case .inactive: .secondary
        }
    }

    var body: some View {
        Text(status.uiLabel(language: language))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: .capsule)
            .foregroundStyle(color)
    }
}
