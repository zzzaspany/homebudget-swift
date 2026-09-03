import Testing

@testable import HomeBudgetCore

@Suite("Localization")
struct LocalizationTests {
    @Test("Amounts format per language without relying on ICU")
    func currency() {
        #expect(NumberFormatting.currency(1234.5, language: .pl) == "1\u{00A0}234,50\u{00A0}zł")
        #expect(NumberFormatting.currency(1234.5, language: .en) == "PLN 1,234.50")
        #expect(NumberFormatting.currency(0, language: .pl) == "0,00\u{00A0}zł")
        #expect(NumberFormatting.currency(1234567.89, language: .en) == "PLN 1,234,567.89")
        #expect(NumberFormatting.currency(-45.5, language: .en) == "PLN -45.50")
    }

    @Test("Rounding follows the two-decimal display contract")
    func rounding() {
        #expect(NumberFormatting.decimal(216.6666, language: .en) == "216.67")
        #expect(NumberFormatting.decimal(0.005, language: .en) == "0.01")
    }

    @Test("Month labels and period markers")
    func months() {
        #expect(Localization.monthAbbreviation(8, language: .pl) == "Sie")
        #expect(Localization.monthAbbreviation(8, language: .en) == "Aug")
        #expect(Localization.projectionLabel(year: 2026, month: 10, language: .pl) == "Paź '26")
        #expect(Localization.periodLabel("2026-08", language: .en) == "Aug 2026")
        #expect(Localization.periodLabel("2026", language: .pl) == "2026")
    }

    @Test("Category names translate only when known")
    func categories() {
        #expect(Localization.category("Media i Eksploatacja", language: .en) == "Utilities & Operations")
        #expect(Localization.category("Media i Eksploatacja", language: .pl) == "Media i Eksploatacja")
        #expect(Localization.category("Własna kategoria", language: .en) == "Własna kategoria")
    }

    @Test("Notification wording, including singular forms")
    func notificationMessages() {
        #expect(Localization.notificationMessage(status: .overdue, daysLeft: -3, language: .pl) == "Po terminie o 3 dni")
        #expect(Localization.notificationMessage(status: .overdue, daysLeft: -1, language: .pl) == "Po terminie o 1 dzień")
        #expect(Localization.notificationMessage(status: .dueSoon, daysLeft: 5, language: .en) == "Due in 5 days")
        #expect(Localization.notificationMessage(status: .dueSoon, daysLeft: 1, language: .en) == "Due in 1 day")
    }

    @Test("Polish alert counts use all three plural forms")
    func alertCounts() {
        #expect(Localization.alertCountLabel(1, language: .pl) == "1 alert")
        #expect(Localization.alertCountLabel(3, language: .pl) == "3 alerty")
        #expect(Localization.alertCountLabel(7, language: .pl) == "7 alertów")
        #expect(Localization.alertCountLabel(12, language: .pl) == "12 alertów")
        #expect(Localization.alertCountLabel(22, language: .pl) == "22 alerty")
    }

    @Test("Report labels for frequencies and statuses")
    func reportLabels() {
        #expect(Frequency.semiAnnual.label(language: .pl) == "Półroczny")
        #expect(Frequency.semiAnnual.label(language: .en) == "Semi-annual")
        #expect(ExpenseStatus.dueSoon.reportLabel(language: .pl) == "WKRÓTCE")
        #expect(ExpenseStatus.dueSoon.reportLabel(language: .en) == "DUE SOON")
    }
}
