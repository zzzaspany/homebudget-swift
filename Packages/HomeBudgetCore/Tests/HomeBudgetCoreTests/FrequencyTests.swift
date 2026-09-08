import Testing

@testable import HomeBudgetCore

@Suite("Recurrence intervals")
struct FrequencyTests {
    @Test("Every cycle maps to an interval a calendar can repeat on")
    func recurrenceIntervals() {
        #expect(Frequency.monthly.recurrenceInterval == .months(1))
        #expect(Frequency.biweekly.recurrenceInterval == .weeks(2))
        #expect(Frequency.quarterly.recurrenceInterval == .months(3))
        #expect(Frequency.semiAnnual.recurrenceInterval == .months(6))
        #expect(Frequency.yearly.recurrenceInterval == .months(12))
    }

    /// The interval has to agree with the proration, or a reminder would fire on a schedule the
    /// budget was never calculating for.
    @Test("Month-aligned intervals match the prorated share")
    func intervalsAgreeWithProration() {
        for frequency in Frequency.allCases {
            guard case .months(let months) = frequency.recurrenceInterval else { continue }
            let prorated = frequency.proratedMonthlyAmount(of: 120)
            #expect(prorated == 120 / Double(months))
        }
    }

    @Test("Biweekly is the only cycle that is not month-aligned")
    func biweeklyIsTheExceptionEverywhere() {
        let weekly = Frequency.allCases.filter {
            if case .weeks = $0.recurrenceInterval { return true }
            return false
        }
        #expect(weekly == [.biweekly])
        #expect(Frequency.biweekly.monthInterval == nil)
    }
}
