/// User-interface text, kept beside the report labels so nothing drifts between the two.
public enum UIString: String, CaseIterable, Sendable {
    case appTitle
    case kpiMonthlyBudget
    case kpiSinkingFund
    case kpiMonthlyDues
    case kpiYearlyDues
    case kpiAlerts

    case sectionExpenses
    case sectionAlerts
    case sectionSinkingFunds
    case sectionCategoryBudgets
    case sectionPaymentHistory
    case sectionCategoryChart
    case sectionProjection
    case chartPeak
    case viewList
    case viewCalendar
    case viewCharts

    case signIn
    case signInPrompt
    case signInTitle
    case actionRefresh
    case actionSignOut
    case errorTitle
    case developMode

    case columnName
    case columnAmount
    case columnFrequency
    case columnDue
    case columnCategory
    case columnStatus
    case columnActions
    case columnPeriod
    case columnPaidBy
    case columnDatePaid
    case columnInvoice
    case invoiceOptional

    case searchPlaceholder
    case filterAllFrequencies
    case filterAllStatuses

    case actionAdd
    case actionEdit
    case actionDelete
    case actionPay
    case actionHistory
    case actionSave
    case actionCancel
    case actionSendEmail

    case emptyExpenses
    case emptyAlerts
    case emptySinkingFunds
    case emptyPayments
    case loading
    case loadFailed
    case retry

    case variableBill
    case monthlyReserve
    case budgetOf
    case overBudget

    public func callAsFunction(_ language: Language) -> String {
        localized(language)
    }

    public func localized(_ language: Language) -> String {
        switch language {
        case .pl: return Self.polish[self] ?? rawValue
        case .en: return Self.english[self] ?? rawValue
        }
    }

    static let polish: [UIString: String] = [
        .appTitle: "HomeBudget",
        .kpiMonthlyBudget: "Budżet miesięczny",
        .kpiSinkingFund: "Miesięczna rezerwa",
        .kpiMonthlyDues: "Zobowiązania miesięczne",
        .kpiYearlyDues: "Zobowiązania roczne",
        .kpiAlerts: "Wymaga uwagi",

        .sectionExpenses: "Wydatki cykliczne",
        .sectionAlerts: "Alerty płatności",
        .sectionSinkingFunds: "Rezerwy na przyszłe opłaty",
        .sectionCategoryBudgets: "Budżety kategorii",
        .sectionPaymentHistory: "Historia wpłat",
        .sectionCategoryChart: "Podział na kategorie",
        .sectionProjection: "Prognoza 12 miesięcy",
        .chartPeak: "Szczyt",
        .viewList: "Lista",
        .viewCalendar: "Kalendarz",
        .viewCharts: "Wykresy",

        .signIn: "Zaloguj się",
        .signInPrompt: "Zaloguj się przez Authelię, tak samo jak w przeglądarce.",
        .signInTitle: "Logowanie",
        .actionRefresh: "Odśwież",
        .actionSignOut: "Wyloguj",
        .errorTitle: "Coś poszło nie tak",
        .developMode: "Tryb deweloperski",

        .columnName: "Nazwa",
        .columnAmount: "Kwota",
        .columnFrequency: "Cykl",
        .columnDue: "Termin",
        .columnCategory: "Kategoria",
        .columnStatus: "Status",
        .columnActions: "Akcje",
        .columnPeriod: "Okres",
        .columnPaidBy: "Opłacił(a)",
        .columnDatePaid: "Data wpłaty",
        .columnInvoice: "Faktura",
        .invoiceOptional: "Faktura (opcjonalnie)",

        .searchPlaceholder: "Szukaj po nazwie lub kategorii…",
        .filterAllFrequencies: "Wszystkie cykle",
        .filterAllStatuses: "Wszystkie statusy",

        .actionAdd: "Dodaj wydatek",
        .actionEdit: "Edytuj",
        .actionDelete: "Usuń",
        .actionPay: "Opłać",
        .actionHistory: "Historia cen",
        .actionSave: "Zapisz",
        .actionCancel: "Anuluj",
        .actionSendEmail: "Wyślij alerty e-mail",

        .emptyExpenses: "Brak wydatków do wyświetlenia.",
        .emptyAlerts: "Nic nie wymaga uwagi.",
        .emptySinkingFunds: "Brak opłat wymagających rezerwy.",
        .emptyPayments: "Brak zarejestrowanych wpłat.",
        .loading: "Wczytywanie…",
        .loadFailed: "Nie udało się wczytać danych",
        .retry: "Spróbuj ponownie",

        .variableBill: "rachunek zmienny",
        .monthlyReserve: "miesięcznie",
        .budgetOf: "z",
        .overBudget: "przekroczono",
    ]

    static let english: [UIString: String] = [
        .appTitle: "HomeBudget",
        .kpiMonthlyBudget: "Monthly budget",
        .kpiSinkingFund: "Monthly reserve",
        .kpiMonthlyDues: "Monthly dues",
        .kpiYearlyDues: "Yearly dues",
        .kpiAlerts: "Needs attention",

        .sectionExpenses: "Recurring expenses",
        .sectionAlerts: "Payment alerts",
        .sectionSinkingFunds: "Reserves for future bills",
        .sectionCategoryBudgets: "Category budgets",
        .sectionPaymentHistory: "Payment history",
        .sectionCategoryChart: "Category breakdown",
        .sectionProjection: "12-month projection",
        .chartPeak: "Peak",
        .viewList: "List",
        .viewCalendar: "Calendar",
        .viewCharts: "Charts",

        .signIn: "Sign in",
        .signInPrompt: "Sign in through Authelia, the same way the browser does.",
        .signInTitle: "Sign in",
        .actionRefresh: "Refresh",
        .actionSignOut: "Sign out",
        .errorTitle: "Something went wrong",
        .developMode: "Develop mode",

        .columnName: "Name",
        .columnAmount: "Amount",
        .columnFrequency: "Cycle",
        .columnDue: "Due",
        .columnCategory: "Category",
        .columnStatus: "Status",
        .columnActions: "Actions",
        .columnPeriod: "Period",
        .columnPaidBy: "Paid by",
        .columnDatePaid: "Payment date",
        .columnInvoice: "Invoice",
        .invoiceOptional: "Invoice (optional)",

        .searchPlaceholder: "Search by name or category…",
        .filterAllFrequencies: "All cycles",
        .filterAllStatuses: "All statuses",

        .actionAdd: "Add expense",
        .actionEdit: "Edit",
        .actionDelete: "Delete",
        .actionPay: "Pay",
        .actionHistory: "Price history",
        .actionSave: "Save",
        .actionCancel: "Cancel",
        .actionSendEmail: "Send e-mail alerts",

        .emptyExpenses: "No expenses to show.",
        .emptyAlerts: "Nothing needs attention.",
        .emptySinkingFunds: "No bills need a reserve.",
        .emptyPayments: "No payments recorded.",
        .loading: "Loading…",
        .loadFailed: "Could not load data",
        .retry: "Try again",

        .variableBill: "variable bill",
        .monthlyReserve: "per month",
        .budgetOf: "of",
        .overBudget: "over budget",
    ]
}

extension ExpenseStatus {
    /// Sentence-case form used in the interface, as opposed to the shouted report labels.
    public func uiLabel(language: Language) -> String {
        switch (self, language) {
        case (.paid, .pl): return "Opłacone"
        case (.overdue, .pl): return "Zaległe"
        case (.dueSoon, .pl): return "Wkrótce"
        case (.upcoming, .pl): return "Nadchodzące"
        case (.inactive, .pl): return "Nieaktywne"
        case (.paid, .en): return "Paid"
        case (.overdue, .en): return "Overdue"
        case (.dueSoon, .en): return "Due soon"
        case (.upcoming, .en): return "Upcoming"
        case (.inactive, .en): return "Inactive"
        }
    }
}
