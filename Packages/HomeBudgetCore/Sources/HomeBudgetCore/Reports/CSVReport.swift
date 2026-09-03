/// Semicolon-delimited CSV, the layout Excel in a Polish locale expects.
public enum CSVReport {
    static let delimiter = ";"
    /// Excel only detects UTF-8 in a `;`-delimited file when the byte-order mark is present.
    public static let byteOrderMark = "\u{FEFF}"

    public static func build(
        dashboard: Dashboard,
        payments: [PaymentRecord],
        userName: String,
        generatedAt: CalendarDate,
        language: Language
    ) -> String {
        var rows: [[String]] = []

        rows.append([language == .pl ? "HOMEBUDGET — RAPORT KOSZTÓW UTRZYMANIA DOMU" : "HOMEBUDGET — HOME MAINTENANCE EXPENSE REPORT"])
        rows.append([language == .pl ? "Data wygenerowania" : "Generation Date", generatedAt.iso8601])
        rows.append([language == .pl ? "Użytkownik" : "User", userName])
        rows.append([])

        rows.append([language == .pl ? "PODSUMOWANIE KPI" : "KPI SUMMARY"])
        let currency = language == .pl ? "zł" : "PLN"
        rows.append([
            language == .pl ? "Średniomiesięczny Budżet (\(currency))" : "Average Monthly Budget (\(currency))",
            amount(dashboard.kpis.proRatedMonthly),
        ])
        rows.append([
            language == .pl ? "Miesięczna Rezerwa (Sinking Fund) (\(currency))" : "Monthly Savings Reserve (Sinking Fund) (\(currency))",
            amount(dashboard.kpis.sinkingFundTotal),
        ])
        rows.append([
            language == .pl ? "Zobowiązania Miesięczne (\(currency))" : "Monthly Expenses (\(currency))",
            amount(dashboard.kpis.monthlyTotal),
        ])
        rows.append([
            language == .pl ? "Zobowiązania Roczne (\(currency))" : "Yearly Expenses (\(currency))",
            amount(dashboard.kpis.yearlyTotal),
        ])
        rows.append([])

        rows.append([language == .pl ? "WYKAZ WYDATKÓW CYKLICZNYCH" : "LIST OF RECURRING EXPENSES"])
        rows.append(
            language == .pl
                ? ["Nazwa wydatku", "Kwota (\(currency))", "Częstotliwość", "Dzień płatności", "Miesiąc", "Kategoria", "Rachunek Zmienny", "Status"]
                : ["Expense Name", "Amount (\(currency))", "Frequency", "Due Day", "Due Month", "Category", "Variable Bill", "Status"]
        )
        for summary in dashboard.expenses {
            let expense = summary.expense
            rows.append([
                expense.name,
                amount(expense.amount),
                expense.frequency.label(language: language),
                "\(expense.dueDay)",
                expense.dueMonth.map { "\($0)" } ?? "-",
                Localization.category(expense.category, language: language),
                yesNo(expense.isVariable, language: language),
                summary.status.reportLabel(language: language),
            ])
        }
        rows.append([])

        rows.append([language == .pl ? "HISTORIA WPŁAT I RACHUNKÓW" : "PAYMENT AND BILL LOGS"])
        rows.append(
            language == .pl
                ? ["Nazwa wydatku", "Kategoria", "Okres", "Zapłacono (\(currency))", "Data wpłaty", "Opłacił(a)"]
                : ["Expense Name", "Category", "Period", "Amount Paid (\(currency))", "Payment Date", "Paid By"]
        )
        for payment in payments {
            rows.append([
                payment.expenseName,
                Localization.category(payment.category, language: language),
                Localization.periodLabel(payment.period, language: language),
                amount(payment.amountPaid),
                payment.datePaid.iso8601,
                payment.paidBy,
            ])
        }

        return byteOrderMark + rows.map(line).joined(separator: "\r\n") + "\r\n"
    }

    static func line(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: delimiter)
    }

    /// Quotes a field only when it would otherwise break the row, doubling any embedded quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(";") || field.contains("\"") || field.contains("\n")
            || field.contains("\r")
        else {
            return field
        }
        let doubled = field.map { $0 == "\"" ? "\"\"" : String($0) }.joined()
        return "\"\(doubled)\""
    }

    /// Amounts stay machine-readable (plain `1234.5`), matching the Python export.
    static func amount(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }

    static func yesNo(_ value: Bool, language: Language) -> String {
        switch (value, language) {
        case (true, .pl): return "TAK"
        case (false, .pl): return "NIE"
        case (true, .en): return "YES"
        case (false, .en): return "NO"
        }
    }
}
