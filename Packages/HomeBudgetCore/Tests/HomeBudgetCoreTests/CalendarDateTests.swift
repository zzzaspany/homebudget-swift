import Testing

@testable import HomeBudgetCore

@Suite("Calendar arithmetic")
struct CalendarDateTests {
    @Test("Days in month, including leap years")
    func daysInMonth() {
        #expect(CalendarDate.daysInMonth(year: 2026, month: 2) == 28)
        #expect(CalendarDate.daysInMonth(year: 2024, month: 2) == 29)
        #expect(CalendarDate.daysInMonth(year: 2000, month: 2) == 29)
        #expect(CalendarDate.daysInMonth(year: 1900, month: 2) == 28)
        #expect(CalendarDate.daysInMonth(year: 2026, month: 4) == 30)
        #expect(CalendarDate.daysInMonth(year: 2026, month: 12) == 31)
    }

    @Test("Day clamping never overflows a short month")
    func clamping() {
        #expect(CalendarDate.clamping(year: 2026, month: 4, day: 31).day == 30)
        #expect(CalendarDate.clamping(year: 2026, month: 2, day: 31).day == 28)
        #expect(CalendarDate.clamping(year: 2024, month: 2, day: 31).day == 29)
        #expect(CalendarDate.clamping(year: 2026, month: 1, day: 15).day == 15)
    }

    @Test("Day arithmetic crosses month and year boundaries")
    func dayArithmetic() {
        let date = CalendarDate(year: 2026, month: 8, day: 15)
        #expect(date.addingDays(14) == CalendarDate(year: 2026, month: 8, day: 29))
        #expect(date.addingDays(20) == CalendarDate(year: 2026, month: 9, day: 4))
        #expect(CalendarDate(year: 2026, month: 12, day: 31).addingDays(1) == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(CalendarDate(year: 2024, month: 2, day: 28).addingDays(1) == CalendarDate(year: 2024, month: 2, day: 29))
    }

    @Test("Days between two dates, signed")
    func daysBetween() {
        let today = CalendarDate(year: 2026, month: 8, day: 15)
        #expect(today.days(until: CalendarDate(year: 2026, month: 8, day: 20)) == 5)
        #expect(today.days(until: CalendarDate(year: 2026, month: 8, day: 10)) == -5)
        #expect(today.days(until: today) == 0)
    }

    @Test("ISO weekday and week number")
    func isoWeek() {
        // 2026-08-15 is a Saturday in ISO week 33.
        let date = CalendarDate(year: 2026, month: 8, day: 15)
        #expect(date.isoWeekday == 6)
        #expect(date.isoWeek == 33)

        // 2026-01-01 is a Thursday, so it belongs to week 1.
        let newYear = CalendarDate(year: 2026, month: 1, day: 1)
        #expect(newYear.isoWeekday == 4)
        #expect(newYear.isoWeek == 1)
    }

    @Test("Round-trips through the Julian day number")
    func julianRoundTrip() {
        for date in [
            CalendarDate(year: 2026, month: 8, day: 15),
            CalendarDate(year: 2000, month: 1, day: 1),
            CalendarDate(year: 2024, month: 2, day: 29),
            CalendarDate(year: 1999, month: 12, day: 31),
        ] {
            #expect(CalendarDate(julianDayNumber: date.julianDayNumber) == date)
        }
    }
}
