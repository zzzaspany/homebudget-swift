#if DEBUG

    import Foundation
    import HomeBudgetCore

    /// Runs the app against sample data, without a server or a sign-in.
    ///
    /// Guarded by `#if DEBUG` rather than read from the environment at run time: a flag that only
    /// exists in a debug build cannot be switched on in a shipped one. An app that can be talked
    /// into skipping authentication is worth more to an attacker than the data behind it.
    ///
    /// Turn it on from the scheme's environment, or on the command line. Note the single dash:
    /// UserDefaults reads `-key value` pairs, and a double dash lands under a different key.
    ///
    ///     xcrun simctl launch booted lab.office.homebudget -DEVELOP_MODE ON
    ///
    /// Or as a real environment variable, which simctl forwards after stripping the prefix:
    ///
    ///     SIMCTL_CHILD_DEVELOP_MODE=ON xcrun simctl launch booted lab.office.homebudget
    enum DevelopMode {
        static var isOn: Bool {
            ProcessInfo.processInfo.environment["DEVELOP_MODE"] == "ON"
                || UserDefaults.standard.string(forKey: "DEVELOP_MODE") == "ON"
        }

        /// Which tab to open on, so a screen can be checked without tapping through to it.
        /// `DEVELOP_TAB=charts` or `calendar`.
        static var initialTab: String? {
            ProcessInfo.processInfo.environment["DEVELOP_TAB"]
        }

        /// Opens a sheet on launch, for screens that are otherwise several taps in.
        /// `DEVELOP_SHEET=history`.
        static var initialSheet: String? {
            ProcessInfo.processInfo.environment["DEVELOP_SHEET"]
        }

        /// A household that exercises every branch worth looking at: overdue, due soon, paid, a
        /// variable bill, and cycles from fortnightly to yearly.
        static let today = CalendarDate.today()

        /// Mutable in develop mode, so the editor and the delete flow can be exercised without a
        /// server. A shipped build has neither this nor the branches that call it.
        ///
        /// Main-actor isolated because it is shared mutable state and Swift 6 says so; every caller
        /// is a view or a view model already.
        @MainActor private static var edits: [Expense]?

        @MainActor static func apply(_ input: ExpenseInput, editing id: String?) {
            var all = expenses
            let expense = Expense(
                id: id ?? "dev-\(Int(Date().timeIntervalSince1970))",
                name: input.name, amount: input.amount, frequency: input.frequency,
                dueDay: input.dueDay, dueMonth: input.dueMonth, category: input.category,
                lastPaidPeriod: id.flatMap { existing in
                    all.first { $0.id == existing }?.lastPaidPeriod
                } ?? "",
                active: input.active, isVariable: input.isVariable)

            if let id, let index = all.firstIndex(where: { $0.id == id }) {
                all[index] = expense
            } else {
                all.append(expense)
            }
            edits = all
        }

        @MainActor static func remove(id: String) {
            edits = expenses.filter { $0.id != id }
        }

        @MainActor static var expenses: [Expense] {
            if let edits { return edits }
            return [
                Expense(
                    id: "1", name: "Kredyt hipoteczny", amount: 2450, frequency: .monthly,
                    dueDay: 1, category: "Kredyt i Ubezpieczenia"),
                Expense(
                    id: "2", name: "Prąd", amount: 245.50, frequency: .monthly, dueDay: 10,
                    category: "Media i Eksploatacja", isVariable: true),
                Expense(
                    id: "3", name: "Gaz", amount: 180, frequency: .monthly, dueDay: 18,
                    category: "Media i Eksploatacja", isVariable: true),
                Expense(
                    id: "4", name: "Internet światłowód", amount: 89, frequency: .monthly,
                    dueDay: 5, category: "Stałe Opłaty"),
                Expense(
                    id: "5", name: "Abonament telefon", amount: 65, frequency: .monthly,
                    dueDay: 12, category: "Stałe Opłaty"),
                Expense(
                    id: "6", name: "Bufor awaryjny", amount: 300, frequency: .monthly, dueDay: 28,
                    category: "Bufor i Rezerwy"),
                Expense(
                    id: "7", name: "Wywóz śmieci", amount: 150, frequency: .quarterly, dueDay: 10,
                    dueMonth: 1, category: "Media i Eksploatacja"),
                Expense(
                    id: "8", name: "Podatek od nieruchomości", amount: 320, frequency: .quarterly,
                    dueDay: 15, dueMonth: 3, category: "Podatki"),
                Expense(
                    id: "9", name: "Woda i kanalizacja", amount: 132, frequency: .quarterly,
                    dueDay: 20, dueMonth: 2, category: "Media i Eksploatacja", isVariable: true),
                Expense(
                    id: "10", name: "Ubezpieczenie domu", amount: 1200, frequency: .yearly,
                    dueDay: 15, dueMonth: 11, category: "Kredyt i Ubezpieczenia"),
                Expense(
                    id: "11", name: "Przegląd pieca", amount: 450, frequency: .yearly, dueDay: 20,
                    dueMonth: 9, category: "Serwisy i Przeglądy"),
                Expense(
                    id: "12", name: "Przegląd kominiarski", amount: 180, frequency: .yearly,
                    dueDay: 5, dueMonth: 10, category: "Serwisy i Przeglądy"),
            ]
        }

        @MainActor static var dashboard: Dashboard {
            DashboardBuilder.build(expenses: expenses, today: today)
        }

        /// Enough history on one bill for the price trend to have something to say.
        @MainActor static var payments: [PaymentRecord] {
            let electricity = [198.40, 231.10, 245.50, 262.30]
            return electricity.enumerated().map { index, amount in
                let month = max(1, today.month - electricity.count + index)
                return PaymentRecord(
                    id: "p\(index)", expenseID: "2", expenseName: "Prąd",
                    category: "Media i Eksploatacja", amountPaid: amount,
                    datePaid: CalendarDate(year: today.year, month: month, day: 12),
                    period: "\(today.year)-\(month < 10 ? "0" : "")\(month)", paidBy: "konrad")
            }.reversed()
        }

        @MainActor static func priceHistory(expenseID: String) -> PriceHistory {
            PriceHistory.build(
                expenseID: expenseID,
                payments: payments.map {
                    Payment(
                        id: $0.id, expenseID: $0.expenseID, amountPaid: $0.amountPaid,
                        datePaid: $0.datePaid, period: $0.period, paidBy: $0.paidBy)
                })
        }
    }

#endif
