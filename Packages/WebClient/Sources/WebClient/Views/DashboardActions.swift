import HomeBudgetCore
import JavaScriptKit

/// The side-effecting half of the dashboard: everything that calls the API or opens a dialog.
extension DashboardView {
    private var api: APIClient { APIClient() }


    // MARK: - Payments

    func pay(expenseID: String, amount: Double?) {
        guard let summary = state.dashboard?.expenses.first(where: { $0.expense.id == expenseID })
        else { return }
        openPaymentDialog(for: summary.expense)
    }

    private func openPaymentDialog(for expense: Expense) {
        let amountField = field(type: "number", value: NumberFormatting.plain(expense.amount))
        amountField.attribute("step", "0.01")
        amountField.attribute("min", "0.01")

        let invoiceField = DOM.element("input", class: "input")
        invoiceField.attribute("type", "file")
        invoiceField.attribute("accept", "application/pdf,image/*")

        let body = DOM.element("div", class: "form").appending(
            labelled(UIString.columnAmount(state.language), amountField),
            labelled(UIString.invoiceOptional(state.language), invoiceField))

        // A variable bill suggests the average of what has been paid before.
        if expense.isVariable {
            let hint = DOM.element("p", class: "muted small", text: UIString.loading(state.language))
            body.appending(hint)
            Task {
                if let history = try? await api.history(expenseID: expense.id),
                    let average = history.averageAmountPaid
                {
                    hint.textContent = .string(
                        "\(UIString.variableBill(state.language)): ⌀ "
                            + NumberFormatting.currency(average, language: state.language))
                    amountField.value = .string(NumberFormatting.plain(average))
                } else {
                    hint.removeFromParent()
                }
            }
        }

        let confirm = DOM.element("button", class: "button primary", text: UIString.actionPay(state.language))
        confirm.on("click") {
            let amount = Double(amountField.value.string ?? "") ?? expense.amount
            Task {
                do {
                    try await api.pay(expenseID: expense.id, amount: amount)
                    Modal.dismiss()
                    Toast.show("\(expense.name): \(NumberFormatting.currency(amount, language: state.language))")
                    onRefresh()
                } catch {
                    Toast.show(String(describing: error), kind: .failure)
                }
            }
        }

        Modal.present(
            title: "\(UIString.actionPay(state.language)) — \(expense.name)",
            body: body,
            actions: [cancelButton(), confirm]
        )
    }

    // MARK: - Create and edit

    func openExpenseEditor(existing: Expense?) {
        let language = state.language

        let nameField = field(type: "text", value: existing?.name ?? "")
        let amountField = field(type: "number", value: existing.map { NumberFormatting.plain($0.amount) } ?? "")
        amountField.attribute("step", "0.01")
        let categoryField = field(type: "text", value: existing?.category ?? "")
        let dueDayField = field(type: "number", value: existing.map { "\($0.dueDay)" } ?? "1")
        dueDayField.attribute("min", "1")
        dueDayField.attribute("max", "31")

        let dueMonthField = DOM.element("select", class: "input")
        for month in 1...12 {
            let option = DOM.element("option", text: Localization.monthAbbreviation(month, language: language))
            option.value = .string("\(month)")
            if existing?.dueMonth == month { option.selected = .boolean(true) }
            dueMonthField.appending(option)
        }
        let dueMonthRow = labelled(UIString.columnDue(language), dueMonthField)

        let frequencyField = DOM.element("select", class: "input")
        for frequency in Frequency.allCases {
            let option = DOM.element("option", text: frequency.label(language: language))
            option.value = .string(frequency.rawValue)
            if existing?.frequency == frequency { option.selected = .boolean(true) }
            frequencyField.appending(option)
        }

        // Only cycles longer than a month need to know which month they land on.
        func syncDueMonthVisibility() {
            let frequency = Frequency(rawValue: frequencyField.value.string ?? "") ?? .monthly
            dueMonthRow.style.display = .string(frequency.requiresDueMonth ? "" : "none")
        }
        frequencyField.on("change") { syncDueMonthVisibility() }

        let variableField = checkbox(checked: existing?.isVariable ?? false)
        let activeField = checkbox(checked: existing?.active ?? true)

        let body = DOM.element("div", class: "form").appending(
            labelled(UIString.columnName(language), nameField),
            labelled(UIString.columnAmount(language), amountField),
            labelled(UIString.columnCategory(language), categoryField),
            labelled(UIString.columnFrequency(language), frequencyField),
            labelled("\(UIString.columnDue(language)) — \(language == .pl ? "dzień" : "day")", dueDayField),
            dueMonthRow,
            inlineCheckbox(UIString.variableBill(language), variableField),
            inlineCheckbox(language == .pl ? "Aktywny" : "Active", activeField)
        )
        syncDueMonthVisibility()

        let save = DOM.element("button", class: "button primary", text: UIString.actionSave(language))
        save.on("click") {
            let frequency = Frequency(rawValue: frequencyField.value.string ?? "") ?? .monthly
            guard let amount = Double(amountField.value.string ?? ""), amount > 0,
                let name = nameField.value.string, !name.isEmpty,
                let category = categoryField.value.string, !category.isEmpty,
                let dueDay = Int(dueDayField.value.string ?? "")
            else {
                Toast.show(language == .pl ? "Uzupełnij wymagane pola" : "Fill in the required fields", kind: .failure)
                return
            }

            let input = ExpenseInput(
                name: name,
                amount: amount,
                frequency: frequency,
                dueDay: dueDay,
                dueMonth: frequency.requiresDueMonth ? Int(dueMonthField.value.string ?? "1") : nil,
                category: category,
                active: activeField.checked.boolean ?? true,
                isVariable: variableField.checked.boolean ?? false
            )

            Task {
                do {
                    if let existing {
                        try await api.updateExpense(id: existing.id, input)
                    } else {
                        try await api.createExpense(input)
                    }
                    Modal.dismiss()
                    Toast.show(name)
                    onRefresh()
                } catch {
                    Toast.show(String(describing: error), kind: .failure)
                }
            }
        }

        Modal.present(
            title: existing == nil ? UIString.actionAdd(language) : UIString.actionEdit(language),
            body: body,
            actions: [cancelButton(), save]
        )
    }

    // MARK: - Delete

    func confirmDelete(_ expense: Expense) {
        let language = state.language
        let question = language == .pl
            ? "Usunąć „\(expense.name)”?"
            : "Delete “\(expense.name)”?"

        let confirm = DOM.element("button", class: "button danger", text: UIString.actionDelete(language))
        confirm.on("click") {
            Task {
                do {
                    try await api.deleteExpense(id: expense.id)
                    Modal.dismiss()
                    Toast.show(expense.name)
                    onRefresh()
                } catch {
                    Modal.dismiss()
                    Toast.show(String(describing: error), kind: .failure)
                }
            }
        }

        Modal.present(
            title: UIString.actionDelete(language),
            body: DOM.element("p", text: question),
            actions: [cancelButton(), confirm]
        )
    }

    // MARK: - Price history

    func showHistory(for expense: Expense) {
        let language = state.language
        let body = DOM.element("div").appending(
            DOM.element("p", class: "muted", text: UIString.loading(language)))

        Modal.present(
            title: "\(UIString.actionHistory(language)) — \(expense.name)",
            body: body,
            actions: [cancelButton(label: UIString.actionCancel(language))]
        )

        Task {
            do {
                let history = try await api.history(expenseID: expense.id)
                body.removeAllChildren()

                guard !history.entries.isEmpty else {
                    body.appending(DOM.element("p", class: "muted", text: UIString.emptyPayments(language)))
                    return
                }

                let change = history.priceChangePercent
                let changeClass = change > 0 ? "danger-text" : (change < 0 ? "success-text" : "muted")
                body.appending(
                    DOM.element(
                        "p", class: "change \(changeClass)",
                        text: "\(change > 0 ? "+" : "")\(change)%")
                )

                let rows = history.entries.map { entry in
                    DOM.element("tr").appending(
                        DOM.element("td", text: Localization.dateLabel(entry.datePaid, language: language)),
                        DOM.element("td", text: Localization.periodLabel(entry.period, language: language)),
                        DOM.element(
                            "td", class: "amount",
                            text: NumberFormatting.currency(entry.amountPaid, language: language))
                    )
                }
                let head = DOM.element("tr").appending(
                    DOM.element("th", text: UIString.columnDatePaid(language)),
                    DOM.element("th", text: UIString.columnPeriod(language)),
                    DOM.element("th", text: UIString.columnAmount(language))
                )
                body.appending(
                    DOM.element("table", class: "table").appending(
                        DOM.element("thead").appending(head),
                        DOM.element("tbody").appending(rows)))
            } catch {
                body.removeAllChildren()
                body.appending(DOM.element("p", class: "danger-text", text: String(describing: error)))
            }
        }
    }

    // MARK: - Category budgets

    func editBudget(for category: String, current: Double) {
        let language = state.language
        let amountField = field(type: "number", value: NumberFormatting.plain(current))
        amountField.attribute("min", "1")

        let save = DOM.element("button", class: "button primary", text: UIString.actionSave(language))
        save.on("click") {
            guard let amount = Double(amountField.value.string ?? ""), amount > 0 else {
                Toast.show(language == .pl ? "Podaj kwotę większą od zera" : "Enter an amount above zero", kind: .failure)
                return
            }
            Preferences.setBudget(amount, for: category)
            Modal.dismiss()
            onRefresh()
        }

        Modal.present(
            title: Localization.category(category, language: language),
            body: DOM.element("div", class: "form").appending(
                labelled(UIString.columnAmount(language), amountField)),
            actions: [cancelButton(), save]
        )
    }

    // MARK: - Form helpers

    private func field(type: String, value: String) -> JSObject {
        let element = DOM.element("input", class: "input")
        element.attribute("type", type)
        element.value = .string(value)
        return element
    }

    private func checkbox(checked: Bool) -> JSObject {
        let element = DOM.element("input")
        element.attribute("type", "checkbox")
        element.checked = .boolean(checked)
        return element
    }

    private func labelled(_ title: String, _ control: JSObject) -> JSObject {
        DOM.element("label", class: "form-row").appending(
            DOM.element("span", class: "form-label", text: title), control)
    }

    private func inlineCheckbox(_ title: String, _ control: JSObject) -> JSObject {
        DOM.element("label", class: "form-row inline").appending(
            control, DOM.element("span", class: "form-label", text: title))
    }

    private func cancelButton(label: String? = nil) -> JSObject {
        let button = DOM.element("button", class: "button", text: label ?? UIString.actionCancel(state.language))
        button.on("click") { Modal.dismiss() }
        return button
    }
}
