import HomeBudgetCore
import JavaScriptKit

/// Renders the whole dashboard into a container element.
@MainActor
struct DashboardView {
    let state: AppState
    /// Rebuilds from the state already loaded — filters, language, theme.
    let onRender: () -> Void
    /// Refetches from the API, then rebuilds — used after anything that changes data.
    let onRefresh: () -> Void

    static let searchFieldID = "expense-search"

    private var language: Language { state.language }

    func render(into root: JSObject) {
        root.removeAllChildren()
        root.appending(header())

        guard let dashboard = state.dashboard else {
            root.appending(state.loadError.map(errorPanel) ?? DOM.element("p", class: "muted", text: UIString.loading(language)))
            return
        }

        root.appending(kpiRow(dashboard.kpis), viewSwitcher())

        guard state.view == .list else {
            root.appending(
                CalendarView(state: state, onRender: onRender, onPay: { pay(expenseID: $0, amount: nil) })
                    .render())
            return
        }

        root.appending(
            DOM.element("div", class: "layout").appending(
                DOM.element("div", class: "column").appending(
                    alertsPanel(dashboard.notifications),
                    categoryChartPanel(dashboard.categoryBreakdown),
                    sinkingFundPanel(dashboard.sinkingFundItems),
                    categoryBudgetPanel()
                ),
                DOM.element("div", class: "column wide").appending(
                    expensePanel(),
                    projectionPanel(dashboard.projection)
                )
            ),
            paymentHistoryPanel()
        )
    }

    // MARK: - Header

    private func header() -> JSObject {
        let title = DOM.element("h1", class: "app-title", text: UIString.appTitle(language))

        let languageButton = DOM.element("button", class: "chip", text: language == .pl ? "PL" : "EN")
        languageButton.on("click") {
            state.language = language == .pl ? .en : .pl
            Preferences.language = state.language
            onRender()
        }

        let themeButton = DOM.element("button", class: "chip", text: state.theme == .dark ? "☾" : "☀")
        themeButton.on("click") {
            state.theme = state.theme.next
            Preferences.theme = state.theme
            applyTheme(state.theme)
            onRender()
        }

        let reports = DOM.element("div", class: "header-actions").appending(
            reportLink("CSV", path: "/api/reports/csv"),
            reportLink("PDF", path: "/api/reports/pdf"),
            languageButton,
            themeButton
        )

        return DOM.element("header", class: "app-header").appending(title, reports)
    }

    /// Switches between the expense list and the month calendar.
    private func viewSwitcher() -> JSObject {
        let group = DOM.element("div", class: "segmented")
        for (view, label) in [
            (MainView.list, UIString.viewList(language)),
            (MainView.calendar, UIString.viewCalendar(language)),
        ] {
            let button = DOM.element(
                "button", class: "segment \(state.view == view ? "active" : "")", text: label)
            button.on("click") {
                state.view = view
                onRender()
            }
            group.appending(button)
        }
        return group
    }

    private func reportLink(_ label: String, path: String) -> JSObject {
        let link = DOM.element("a", class: "chip", text: label)
        link.attribute("href", "\(path)?lang=\(language.rawValue)")
        link.attribute("target", "_blank")
        return link
    }

    // MARK: - KPIs

    private func kpiRow(_ kpis: Dashboard.KPIs) -> JSObject {
        let alerts = kpis.overdueCount + kpis.dueSoonCount
        return DOM.element("section", class: "kpi-row").appending(
            kpiCard(.kpiMonthlyBudget, money(kpis.proRatedMonthly), accent: "primary"),
            kpiCard(.kpiSinkingFund, money(kpis.sinkingFundTotal), accent: "info"),
            kpiCard(.kpiMonthlyDues, money(kpis.monthlyTotal)),
            kpiCard(.kpiYearlyDues, money(kpis.yearlyTotal)),
            kpiCard(
                .kpiAlerts, "\(alerts)",
                accent: kpis.overdueCount > 0 ? "danger" : (alerts > 0 ? "warning" : nil))
        )
    }

    private func kpiCard(_ label: UIString, _ value: String, accent: String? = nil) -> JSObject {
        DOM.element("div", class: "card kpi \(accent.map { "kpi-\($0)" } ?? "")").appending(
            DOM.element("span", class: "kpi-label", text: label(language)),
            DOM.element("strong", class: "kpi-value", text: value)
        )
    }

    // MARK: - Alerts

    private func alertsPanel(_ notifications: [Dashboard.NotificationItem]) -> JSObject {
        let panel = card(title: .sectionAlerts, badge: notifications.isEmpty ? nil : "\(notifications.count)")

        guard !notifications.isEmpty else {
            return panel.appending(empty(.emptyAlerts))
        }

        let rows = notifications.map { item -> JSObject in
            let message = Localization.notificationMessage(
                status: item.status, daysLeft: item.daysLeft, language: language)

            let payButton = DOM.element("button", class: "icon-button", text: "✓")
            payButton.attribute("title", UIString.actionPay(language))
            payButton.on("click") { pay(expenseID: item.id, amount: nil) }

            return DOM.element("div", class: "alert-row \(item.status == .overdue ? "overdue" : "due-soon")")
                .appending(
                    DOM.element("div", class: "grow").appending(
                        DOM.element("strong", text: item.name),
                        DOM.element("span", class: "muted small", text: message)
                    ),
                    DOM.element("span", class: "amount", text: money(item.amount)),
                    payButton
                )
        }

        let emailButton = DOM.element(
            "button", class: "button subtle", text: UIString.actionSendEmail(language))
        emailButton.on("click") { sendEmailAlerts(from: emailButton) }

        return panel.appending(rows).appending(
            DOM.element("div", class: "panel-footer").appending(emailButton))
    }

    // MARK: - Charts

    private func categoryChartPanel(_ shares: [Dashboard.CategoryShare]) -> JSObject {
        card(title: .sectionCategoryChart)
            .appending(Charts.doughnut(shares, language: language))
    }

    private func projectionPanel(_ entries: [Dashboard.ProjectionEntry]) -> JSObject {
        card(title: .sectionProjection)
            .appending(Charts.projection(entries, language: language))
    }

    // MARK: - Sinking funds

    private func sinkingFundPanel(_ items: [Dashboard.SinkingFundItem]) -> JSObject {
        let panel = card(title: .sectionSinkingFunds)
        guard !items.isEmpty else { return panel.appending(empty(.emptySinkingFunds)) }

        return panel.appending(
            items.sorted { $0.monthlyReserve > $1.monthlyReserve }.map { item in
                DOM.element("div", class: "list-row").appending(
                    DOM.element("div", class: "grow").appending(
                        DOM.element("strong", text: item.name),
                        DOM.element(
                            "span", class: "muted small",
                            text: item.frequency.label(language: language))
                    ),
                    DOM.element("span", class: "amount", text: money(item.monthlyReserve))
                )
            }
        )
    }

    // MARK: - Category budgets

    private func categoryBudgetPanel() -> JSObject {
        let panel = card(title: .sectionCategoryBudgets)
        let progress = state.categoryBudgetProgress
        guard !progress.isEmpty else { return panel.appending(empty(.emptyExpenses)) }

        return panel.appending(
            progress.map { entry in
                let ratio = entry.spent / entry.limit
                let over = ratio > 1
                let bar = DOM.element("div", class: "bar")
                let fill = DOM.element("div", class: "bar-fill \(over ? "over" : "")")
                fill.style.width = .string("\(min(ratio, 1) * 100)%")
                bar.appending(fill)

                let editButton = DOM.element("button", class: "icon-button", text: "✎")
                editButton.on("click") { editBudget(for: entry.category, current: entry.limit) }

                return DOM.element("div", class: "budget-row").appending(
                    DOM.element("div", class: "budget-head").appending(
                        DOM.element(
                            "span", class: "grow",
                            text: Localization.category(entry.category, language: language)),
                        DOM.element(
                            "span", class: "muted small \(over ? "danger-text" : "")",
                            text: "\(money(entry.spent)) \(UIString.budgetOf(language)) \(money(entry.limit))"
                        ),
                        editButton
                    ),
                    bar
                )
            }
        )
    }

    // MARK: - Expenses

    private func expensePanel() -> JSObject {
        let panel = card(title: .sectionExpenses)

        let search = DOM.element("input", class: "input grow")
        search.id = .string(Self.searchFieldID)
        search.attribute("type", "search")
        search.attribute("placeholder", UIString.searchPlaceholder(language))
        search.value = .string(state.search)
        search.on("input") {
            state.search = search.value.string ?? ""
            onRender()
        }

        let frequencySelect = select(
            options: [(nil, UIString.filterAllFrequencies(language))]
                + Frequency.allCases.map { ($0.rawValue, $0.label(language: language)) },
            selected: state.frequencyFilter?.rawValue
        ) { value in
            state.frequencyFilter = value.flatMap(Frequency.init(rawValue:))
            onRender()
        }

        let statusSelect = select(
            options: [(nil, UIString.filterAllStatuses(language))]
                + [ExpenseStatus.overdue, .dueSoon, .upcoming, .paid, .inactive].map {
                    ($0.rawValue, $0.uiLabel(language: language))
                },
            selected: state.statusFilter?.rawValue
        ) { value in
            state.statusFilter = value.flatMap(ExpenseStatus.init(rawValue:))
            onRender()
        }

        let addButton = DOM.element("button", class: "button primary", text: UIString.actionAdd(language))
        addButton.on("click") { openExpenseEditor(existing: nil) }

        panel.appending(
            DOM.element("div", class: "toolbar").appending(search, frequencySelect, statusSelect, addButton)
        )

        let expenses = state.visibleExpenses
        guard !expenses.isEmpty else { return panel.appending(empty(.emptyExpenses)) }

        let head = DOM.element("tr").appending(
            ([.columnName, .columnAmount, .columnFrequency, .columnDue, .columnStatus, .columnActions] as [UIString])
                .map { DOM.element("th", text: $0(language)) }
        )

        let body = DOM.element("tbody").appending(expenses.map(expenseRow))
        let table = DOM.element("table", class: "table").appending(
            DOM.element("thead").appending(head), body)

        return panel.appending(DOM.element("div", class: "table-scroll").appending(table))
    }

    private func expenseRow(_ summary: Dashboard.ExpenseSummary) -> JSObject {
        let expense = summary.expense

        let name = DOM.element("td").appending(
            DOM.element("strong", text: expense.name),
            DOM.element(
                "span", class: "muted small",
                text: Localization.category(expense.category, language: language)
                    + (expense.isVariable ? " · \(UIString.variableBill(language))" : ""))
        )

        let due = summary.dueDate.map { Localization.dateLabel($0, language: language) } ?? "—"

        let payButton = DOM.element("button", class: "icon-button", text: "✓")
        payButton.attribute("title", UIString.actionPay(language))
        payButton.on("click") { pay(expenseID: expense.id, amount: nil) }

        let historyButton = DOM.element("button", class: "icon-button", text: "↗")
        historyButton.attribute("title", UIString.actionHistory(language))
        historyButton.on("click") { showHistory(for: expense) }

        let editButton = DOM.element("button", class: "icon-button", text: "✎")
        editButton.attribute("title", UIString.actionEdit(language))
        editButton.on("click") { openExpenseEditor(existing: expense) }

        let deleteButton = DOM.element("button", class: "icon-button danger", text: "✕")
        deleteButton.attribute("title", UIString.actionDelete(language))
        deleteButton.on("click") { confirmDelete(expense) }

        return DOM.element("tr", class: expense.active ? "" : "inactive").appending(
            name,
            DOM.element("td", class: "amount", text: money(expense.amount)),
            DOM.element("td", text: expense.frequency.label(language: language)),
            DOM.element("td", text: due),
            DOM.element("td").appending(statusBadge(summary.status)),
            DOM.element("td", class: "actions").appending(
                payButton, historyButton, editButton, deleteButton)
        )
    }

    private func statusBadge(_ status: ExpenseStatus) -> JSObject {
        DOM.element("span", class: "badge \(status.rawValue)", text: status.uiLabel(language: language))
    }

    // MARK: - Payment history

    private func paymentHistoryPanel() -> JSObject {
        let panel = card(title: .sectionPaymentHistory)
        guard !state.payments.isEmpty else { return panel.appending(empty(.emptyPayments)) }

        let head = DOM.element("tr").appending(
            ([.columnName, .columnCategory, .columnPeriod, .columnAmount, .columnDatePaid, .columnPaidBy, .columnInvoice] as [UIString])
                .map { DOM.element("th", text: $0(language)) }
        )

        let rows = state.payments.prefix(25).map { payment in
            DOM.element("tr").appending(
                DOM.element("td", text: payment.expenseName),
                DOM.element("td", text: Localization.category(payment.category, language: language)),
                DOM.element("td", text: Localization.periodLabel(payment.period, language: language)),
                DOM.element("td", class: "amount", text: money(payment.amountPaid)),
                DOM.element("td", text: Localization.dateLabel(payment.datePaid, language: language)),
                DOM.element("td", text: payment.paidBy),
                DOM.element("td").appending(invoiceLink(payment))
            )
        }

        let table = DOM.element("table", class: "table").appending(
            DOM.element("thead").appending(head),
            DOM.element("tbody").appending(Array(rows))
        )
        return panel.appending(DOM.element("div", class: "table-scroll").appending(table))
    }

    /// Invoices are financial documents, so they are fetched through an authenticated route
    /// rather than served as static files.
    private func invoiceLink(_ payment: PaymentRecord) -> JSObject {
        guard payment.hasInvoice else {
            return DOM.element("span", class: "muted", text: "—")
        }
        let link = DOM.element("a", class: "chip", text: "↓")
        link.attribute("href", "/api/payments/\(payment.id)/invoice")
        link.attribute("target", "_blank")
        link.attribute("title", UIString.columnInvoice(language))
        return link
    }

    // MARK: - Building blocks

    private func card(title: UIString, badge: String? = nil) -> JSObject {
        let heading = DOM.element("div", class: "card-head").appending(
            DOM.element("h2", text: title(language)))
        if let badge {
            heading.appending(DOM.element("span", class: "count-badge", text: badge))
        }
        return DOM.element("section", class: "card").appending(heading)
    }

    private func empty(_ message: UIString) -> JSObject {
        DOM.element("p", class: "muted", text: message(language))
    }

    private func errorPanel(_ message: String) -> JSObject {
        let retry = DOM.element("button", class: "button", text: UIString.retry(language))
        retry.on("click") { onRefresh() }
        return DOM.element("section", class: "card").appending(
            DOM.element("h2", text: UIString.loadFailed(language)),
            DOM.element("p", class: "muted", text: message),
            retry
        )
    }

    private func select(
        options: [(String?, String)], selected: String?, onChange: @escaping (String?) -> Void
    ) -> JSObject {
        let element = DOM.element("select", class: "input")
        for (value, label) in options {
            let option = DOM.element("option", text: label)
            option.value = .string(value ?? "")
            if value == selected { option.selected = .boolean(true) }
            element.appending(option)
        }
        element.on("change") {
            let raw = element.value.string ?? ""
            onChange(raw.isEmpty ? nil : raw)
        }
        return element
    }

    private func money(_ amount: Double) -> String {
        NumberFormatting.currency(amount, language: language)
    }
}
