import Testing

@testable import HomeBudgetCore

@Suite("CSV export")
struct CSVReportTests {
    let today = CalendarDate(year: 2026, month: 8, day: 15)

    var dashboard: Dashboard {
        DashboardBuilder.build(
            expenses: [
                Expense(
                    id: "exp1", name: "Prąd", amount: 1000, frequency: .monthly, dueDay: 10,
                    category: "Media i Eksploatacja"),
                Expense(
                    id: "exp2", name: "Ubezpieczenie OC", amount: 1200, frequency: .yearly,
                    dueDay: 15, dueMonth: 5, category: "Podatki"),
            ],
            today: today
        )
    }

    var payments: [PaymentRecord] {
        [
            PaymentRecord(
                id: "p1", expenseID: "exp1", expenseName: "Prąd", category: "Media i Eksploatacja",
                amountPaid: 245.5, datePaid: CalendarDate(year: 2026, month: 7, day: 3),
                period: "2026-07", paidBy: "konrad")
        ]
    }

    func report(_ language: Language) -> String {
        CSVReport.build(
            dashboard: dashboard, payments: payments, userName: "Konrad Zielinski",
            generatedAt: today, language: language)
    }

    @Test("Excel-compatible framing: BOM, semicolons, CRLF")
    func framing() {
        let csv = report(.pl)
        #expect(csv.hasPrefix(CSVReport.byteOrderMark))
        #expect(csv.contains("Nazwa wydatku;Kwota (zł);Częstotliwość"))
        #expect(csv.contains("\r\n"))
    }

    @Test("Polish diacritics survive intact")
    func diacritics() {
        let csv = report(.pl)
        #expect(csv.contains("Prąd"))
        #expect(csv.contains("HOMEBUDGET — RAPORT KOSZTÓW UTRZYMANIA DOMU"))
        #expect(csv.contains("Częstotliwość"))
    }

    @Test("Amounts stay machine-readable")
    func amounts() {
        #expect(CSVReport.amount(1000) == "1000")
        #expect(CSVReport.amount(245.5) == "245.5")
        #expect(CSVReport.amount(216.6666) == "216.67")
    }

    @Test("Every label follows the requested language")
    func translation() {
        let polish = report(.pl)
        #expect(polish.contains("Media i Eksploatacja"))
        #expect(polish.contains(";NIE;"))
        #expect(polish.contains("Lip 2026"))

        let english = report(.en)
        #expect(english.contains("HOME MAINTENANCE EXPENSE REPORT"))
        #expect(english.contains("Utilities & Operations"))
        #expect(english.contains(";NO;"))
        #expect(english.contains("Jul 2026"))
    }

    @Test("Fields that would break a row are quoted")
    func escaping() {
        #expect(CSVReport.escape("a;b") == "\"a;b\"")
        #expect(CSVReport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(CSVReport.escape("plain") == "plain")
        #expect(CSVReport.escape("two\nlines") == "\"two\nlines\"")
    }

    @Test("Both report sections are present")
    func sections() {
        let csv = report(.pl)
        #expect(csv.contains("PODSUMOWANIE KPI"))
        #expect(csv.contains("WYKAZ WYDATKÓW CYKLICZNYCH"))
        #expect(csv.contains("HISTORIA WPŁAT I RACHUNKÓW"))
    }
}
