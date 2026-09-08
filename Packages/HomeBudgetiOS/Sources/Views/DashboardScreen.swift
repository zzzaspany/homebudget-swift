import HomeBudgetCore
import SwiftUI
import WidgetKit

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
                publishToWidget()
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
            publishToWidget()
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates or updates, depending on whether an identifier came with it.
    ///
    /// In develop mode the change is applied to the sample data instead, so the form can be worked
    /// on without a server or a sign-in behind it.
    /// Pushes everything derived from the dashboard back out: the widget's snapshot and the
    /// scheduled warnings.
    ///
    /// Called on every path that changes the dashboard, so neither the tile nor the notifications
    /// lag behind the screen the user just looked at.
    private func publishToWidget() {
        guard let dashboard else { return }
        SharedStore.write(UpcomingSnapshot.from(dashboard))
        WidgetCenter.shared.reloadAllTimelines()
        Task { await DueNotifications.reschedule(from: dashboard, language: .device) }
    }

    func save(_ input: ExpenseInput, editing id: String?) async {
        #if DEBUG
            if DevelopMode.isOn {
                DevelopMode.apply(input, editing: id)
                dashboard = DevelopMode.dashboard
                publishToWidget()
                return
            }
        #endif

        do {
            if let id {
                try await client.updateExpense(id: id, input)
            } else {
                try await client.createExpense(input)
            }
            await load()
        } catch APIError.signedOut {
            await session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ expense: Expense) async {
        #if DEBUG
            if DevelopMode.isOn {
                DevelopMode.remove(id: expense.id)
                dashboard = DevelopMode.dashboard
                publishToWidget()
                return
            }
        #endif

        do {
            try await client.deleteExpense(id: expense.id)
            await load()
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
    /// Shared with the More tab, so both see the same export state.
    let reminders: ReminderExport
    @State private var payTarget: Expense?
    @State private var historyTarget: Expense?
    @State private var calendarTarget: Dashboard.ExpenseSummary?
    @State private var editorTarget: EditorTarget?
    @State private var search = ""
    @State private var frequencyFilter: Frequency?
    @State private var statusFilter: ExpenseStatus?
    @State private var deleteTarget: Expense?
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Two columns on a phone, four across an iPad. An adaptive grid packs the cards against the
    /// leading edge at their minimum width instead of spreading them, which left most of an iPad's
    /// width empty and wrapped the amounts onto two lines.
    private var summaryColumns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    private var language: Language { .device }

    /// Search matches the name or the category, in whichever language the category is shown in —
    /// looking for "Utilities" should find a category stored as "Media i Eksploatacja".
    private func matches(_ summary: Dashboard.ExpenseSummary) -> Bool {
        if let frequencyFilter, summary.expense.frequency != frequencyFilter { return false }
        if let statusFilter, summary.status != statusFilter { return false }

        let needle = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return true }

        let haystack = [
            summary.expense.name,
            summary.expense.category,
            Localization.category(summary.expense.category, language: language),
        ]
        return haystack.contains { $0.lowercased().contains(needle) }
    }

    private var isFiltering: Bool {
        frequencyFilter != nil || statusFilter != nil || !search.isEmpty
    }

    private var reminderMessage: String? {
        switch reminders.lastOutcome {
        case .added: return UIString.remindersAdded(language)
        case .updated(0): return UIString.remindersRemoved(language)
        case .updated: return UIString.remindersUpdated(language)
        case .denied: return UIString.remindersDenied(language)
        case .failed(let message): return message
        case nil: return nil
        }
    }

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
            .searchable(text: $search, prompt: UIString.searchPlaceholder(language))
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
                    Button(UIString.actionAdd(language), systemImage: "plus") {
                        editorTarget = EditorTarget(expense: nil)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(UIString.actionRefresh(language), systemImage: "arrow.clockwise") {
                            Task { await model.load() }
                        }

                        Section {
                            Button(
                                reminders.hasExported
                                    ? UIString.actionUpdateReminders(language)
                                    : UIString.actionExportReminders(language),
                                systemImage: "checklist"
                            ) {
                                Task {
                                    await reminders.export(
                                        model.dashboard?.expenses ?? [],
                                        listName: UIString.remindersListName(language))
                                }
                            }
                            .disabled(model.dashboard == nil || reminders.isExporting)

                            if reminders.hasExported {
                                Button(
                                    UIString.actionRemoveReminders(language),
                                    systemImage: "checklist.unchecked", role: .destructive
                                ) {
                                    Task { await reminders.removeAll() }
                                }
                            }
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
            .sheet(item: $editorTarget) { target in
                ExpenseEditor(existing: target.expense) { input in
                    Task { await model.save(input, editing: target.expense?.id) }
                }
            }
            // A real binding, not `.constant`: dismissing by tapping outside has to clear the
            // target too, or the dialog comes straight back.
            .confirmationDialog(
                UIString.deleteConfirmTitle(language),
                isPresented: Binding(
                    get: { deleteTarget != nil },
                    set: { if !$0 { deleteTarget = nil } }),
                titleVisibility: .visible
            ) {
                Button(UIString.actionDelete(language), role: .destructive) {
                    if let expense = deleteTarget {
                        Task { await model.delete(expense) }
                    }
                    deleteTarget = nil
                }
                Button(UIString.actionCancel(language), role: .cancel) { deleteTarget = nil }
            } message: {
                Text(UIString.deleteConfirmMessage(language))
            }
            .sheet(item: $calendarTarget) { summary in
                if let due = summary.dueDate {
                    EventEditSheet(expense: summary.expense, dueDate: due) { _ in
                        calendarTarget = nil
                    }
                    .ignoresSafeArea()
                }
            }
            .alert(
                reminderMessage ?? "",
                isPresented: .constant(reminders.lastOutcome != nil)
            ) {
                Button("OK") { reminders.acknowledge() }
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
        let shown = summaries.filter(matches)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(UIString.sectionExpenses(language))
                    .font(.headline)
                if isFiltering {
                    Text("\(shown.count)/\(summaries.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if shown.isEmpty {
                Text(UIString.emptyExpenses(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            }

            ForEach(shown) { summary in
                ExpenseRow(
                    summary: summary, language: language,
                    onPay: { payTarget = summary.expense },
                    onHistory: { historyTarget = summary.expense },
                    onAddToCalendar: {
                        Task {
                            guard await CalendarAccess.request() else { return }
                            calendarTarget = summary
                        }
                    },
                    onEdit: { editorTarget = EditorTarget(expense: summary.expense) },
                    onDelete: { deleteTarget = summary.expense })
            }
        }
    }
}

struct ExpenseRow: View {
    let summary: Dashboard.ExpenseSummary
    let language: Language
    let onPay: () -> Void
    let onHistory: () -> Void
    let onAddToCalendar: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

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
        .contextMenu {
            Button(UIString.actionHistory(language), systemImage: "chart.line.uptrend.xyaxis", action: onHistory)
            Button(UIString.actionAddToCalendar(language), systemImage: "calendar.badge.plus", action: onAddToCalendar)
            Divider()
            Button(UIString.actionEdit(language), systemImage: "pencil", action: onEdit)
            Button(UIString.actionDelete(language), systemImage: "trash", role: .destructive, action: onDelete)
        }
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


/// Wraps the editor's subject so `sheet(item:)` can tell "add" from "edit" — a nil expense is a
/// valid state for the sheet, which an optional binding alone cannot express.
struct EditorTarget: Identifiable {
    let expense: Expense?
    var id: String { expense?.id ?? "new" }
}
