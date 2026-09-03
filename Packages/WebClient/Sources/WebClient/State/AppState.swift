import HomeBudgetCore

/// Everything the UI renders from, plus the filters applied to it.
@MainActor
final class AppState {
    private(set) var dashboard: Dashboard?
    private(set) var payments: [PaymentRecord] = []
    private(set) var loadError: String?

    var language: Language = Preferences.language
    var theme: Theme = Preferences.theme

    var search: String = ""
    var frequencyFilter: Frequency?
    var statusFilter: ExpenseStatus?

    var view: MainView = .list
    var calendarYear: Int = CalendarDate.today().year
    var calendarMonth: Int = CalendarDate.today().month

    private let api = APIClient()

    func reload() async {
        do {
            async let dashboard = api.dashboard()
            async let payments = api.payments()
            self.dashboard = try await dashboard
            self.payments = try await payments
            loadError = nil
        } catch {
            loadError = String(describing: error)
        }
    }

    /// Expenses after the search box and the two dropdown filters.
    var visibleExpenses: [Dashboard.ExpenseSummary] {
        guard let dashboard else { return [] }
        let needle = search.trimmingCharactersInWhitespace().lowercased()

        return dashboard.expenses.filter { summary in
            let expense = summary.expense
            if let frequencyFilter, expense.frequency != frequencyFilter { return false }
            if let statusFilter, summary.status != statusFilter { return false }
            guard !needle.isEmpty else { return true }
            return expense.name.lowercased().contains(needle)
                || expense.category.lowercased().contains(needle)
        }
    }

    /// Spend per category against the ceiling stored for it, for the budget bars.
    var categoryBudgetProgress: [(category: String, spent: Double, limit: Double)] {
        guard let dashboard else { return [] }
        return dashboard.categoryBreakdown.compactMap { share in
            guard let limit = Preferences.budget(for: share.category), limit > 0 else { return nil }
            return (share.category, share.proratedAmount, limit)
        }
    }
}

enum MainView: String {
    case list
    case calendar
}

extension String {
    /// `Foundation.trimmingCharacters(in:)` is avoided so this stays usable in a WebAssembly build.
    func trimmingCharactersInWhitespace() -> String {
        var characters = Array(self)
        while let first = characters.first, first == " " || first == "\t" || first == "\n" {
            characters.removeFirst()
        }
        while let last = characters.last, last == " " || last == "\t" || last == "\n" {
            characters.removeLast()
        }
        return String(characters)
    }
}
