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
    case actionExportReminders
    case actionUpdateReminders
    case actionRemoveReminders
    case actionAddToCalendar
    case remindersListName
    case remindersAdded
    case remindersUpdated
    case remindersRemoved
    case remindersDenied

    case addExpenseTitle
    case editExpenseTitle
    case fieldDueDay
    case fieldDueMonth
    case fieldActive
    case fieldVariable
    case deleteConfirmTitle
    case deleteConfirmMessage
    case validationName
    case validationAmount
    case validationCategory

    case tabMore
    case sectionReports
    case sectionSettings
    case reportCSV
    case reportPDF
    case serverAddress
    case serverAddressHint
    case budgetLimit
    case budgetNoLimit
    case budgetOverBy
    case remindersSyncPaid
    case remindersSyncNone
    case remindersSyncDone
    case filterTitle
    case filterClear
    case emailSent
    case notificationsEnable
    case notificationsDenied
    case notificationsScheduled
    case notificationsHint
    case suggestionUse
    case suggestionSameMonth
    case suggestionSameMonthAverage
    case suggestionOverallAverage
    case remindersFoundTitle
    case remindersFoundBody
    case remindersRecord
    case remindersLater

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
        .actionExportReminders: "Dodaj do Przypomnień",
        .actionUpdateReminders: "Odśwież Przypomnienia",
        .actionRemoveReminders: "Usuń z Przypomnień",
        .actionAddToCalendar: "Dodaj do Kalendarza",
        .remindersListName: "HomeBudget",
        .remindersAdded: "Dodano do Przypomnień",
        .remindersUpdated: "Przypomnienia zaktualizowane",
        .remindersRemoved: "Usunięto z Przypomnień",
        .remindersDenied: "Brak dostępu do Przypomnień. Włącz go w Ustawieniach › Prywatność.",

        .addExpenseTitle: "Nowy wydatek",
        .editExpenseTitle: "Edytuj wydatek",
        .fieldDueDay: "Dzień miesiąca",
        .fieldDueMonth: "Miesiąc",
        .fieldActive: "Aktywny",
        .fieldVariable: "Rachunek zmienny",
        .deleteConfirmTitle: "Usunąć ten wydatek?",
        .deleteConfirmMessage: "Historia wpłat zostanie zachowana.",
        .validationName: "Podaj nazwę.",
        .validationAmount: "Kwota musi być większa od zera.",
        .validationCategory: "Wybierz kategorię.",

        .tabMore: "Więcej",
        .sectionReports: "Raporty",
        .sectionSettings: "Ustawienia",
        .reportCSV: "Pobierz CSV",
        .reportPDF: "Pobierz PDF",
        .serverAddress: "Adres serwera",
        .serverAddressHint: "Zmiana wymaga ponownego zalogowania.",
        .budgetLimit: "Limit",
        .budgetNoLimit: "Bez limitu",
        .budgetOverBy: "przekroczono o",
        .remindersSyncPaid: "Zapisz odhaczone jako wpłaty",
        .remindersSyncNone: "Nic nie odhaczono.",
        .remindersSyncDone: "Zapisano wpłat:",
        .filterTitle: "Filtry",
        .filterClear: "Wyczyść",
        .emailSent: "Alerty wysłane.",
        .notificationsEnable: "Powiadamiaj o terminach",
        .notificationsDenied: "Brak zgody na powiadomienia. Włącz ją w Ustawieniach › Powiadomienia.",
        .notificationsScheduled: "Zaplanowano przypomnień:",
        .notificationsHint: "Powiadomienie przyjdzie tyle dni przed terminem, ile wynosi próg danego cyklu.",
        .suggestionUse: "Wstaw",
        .suggestionSameMonth: "tyle samo co w tym miesiącu rok temu",
        .suggestionSameMonthAverage: "średnia z tego miesiąca w poprzednich latach",
        .suggestionOverallAverage: "średnia ze wszystkich wpłat",
        .remindersFoundTitle: "Odhaczone przypomnienia",
        .remindersFoundBody: "Zapisać je jako wpłaty?",
        .remindersRecord: "Zapisz",
        .remindersLater: "Nie teraz",

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
        .actionExportReminders: "Add to Reminders",
        .actionUpdateReminders: "Refresh Reminders",
        .actionRemoveReminders: "Remove from Reminders",
        .actionAddToCalendar: "Add to Calendar",
        .remindersListName: "HomeBudget",
        .remindersAdded: "Added to Reminders",
        .remindersUpdated: "Reminders updated",
        .remindersRemoved: "Removed from Reminders",
        .remindersDenied: "No access to Reminders. Grant it in Settings › Privacy.",

        .addExpenseTitle: "New expense",
        .editExpenseTitle: "Edit expense",
        .fieldDueDay: "Day of month",
        .fieldDueMonth: "Month",
        .fieldActive: "Active",
        .fieldVariable: "Variable bill",
        .deleteConfirmTitle: "Delete this expense?",
        .deleteConfirmMessage: "Its payment history is kept.",
        .validationName: "Give it a name.",
        .validationAmount: "The amount must be greater than zero.",
        .validationCategory: "Pick a category.",

        .tabMore: "More",
        .sectionReports: "Reports",
        .sectionSettings: "Settings",
        .reportCSV: "Download CSV",
        .reportPDF: "Download PDF",
        .serverAddress: "Server address",
        .serverAddressHint: "Changing this means signing in again.",
        .budgetLimit: "Limit",
        .budgetNoLimit: "No limit",
        .budgetOverBy: "over by",
        .remindersSyncPaid: "Record ticked-off reminders as payments",
        .remindersSyncNone: "Nothing was ticked off.",
        .remindersSyncDone: "Payments recorded:",
        .filterTitle: "Filters",
        .filterClear: "Clear",
        .emailSent: "Alerts sent.",
        .notificationsEnable: "Warn me before bills are due",
        .notificationsDenied: "Notifications are not permitted. Allow them in Settings › Notifications.",
        .notificationsScheduled: "Warnings scheduled:",
        .notificationsHint: "The warning arrives as many days ahead as that cycle's own threshold.",
        .suggestionUse: "Use",
        .suggestionSameMonth: "what this month cost a year ago",
        .suggestionSameMonthAverage: "average for this month in earlier years",
        .suggestionOverallAverage: "average of every payment",
        .remindersFoundTitle: "Ticked-off reminders",
        .remindersFoundBody: "Record them as payments?",
        .remindersRecord: "Record",
        .remindersLater: "Not now",

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
