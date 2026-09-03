/// A timezone-free calendar date.
///
/// Deliberately not built on `Foundation.Date`/`Calendar`: the same arithmetic has to produce
/// identical results on a Linux server and inside a WebAssembly build, where ICU/locale data
/// availability is unreliable.
public struct CalendarDate: Codable, Hashable, Comparable, Sendable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 30
        }
    }

    /// Builds a date clamping the day to the last valid day of that month (e.g. day 31 in April becomes 30).
    public static func clamping(year: Int, month: Int, day: Int) -> CalendarDate {
        CalendarDate(year: year, month: month, day: min(day, daysInMonth(year: year, month: month)))
    }

    public var julianDayNumber: Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    public init(julianDayNumber jdn: Int) {
        let a = jdn + 32044
        let b = (4 * a + 3) / 146097
        let c = a - 146097 * b / 4
        let d = (4 * c + 3) / 1461
        let e = c - 1461 * d / 4
        let m = (5 * e + 2) / 153
        self.day = e - (153 * m + 2) / 5 + 1
        self.month = m + 3 - 12 * (m / 10)
        self.year = 100 * b + d - 4800 + m / 10
    }

    public func addingDays(_ count: Int) -> CalendarDate {
        CalendarDate(julianDayNumber: julianDayNumber + count)
    }

    /// Days from `self` to `other`; negative when `other` is in the past.
    public func days(until other: CalendarDate) -> Int {
        other.julianDayNumber - julianDayNumber
    }

    /// ISO-8601 weekday, Monday == 1 through Sunday == 7.
    public var isoWeekday: Int {
        julianDayNumber % 7 + 1
    }

    /// ISO-8601 week number (the week containing this date's Thursday).
    public var isoWeek: Int {
        let thursday = addingDays(4 - isoWeekday)
        let jan1 = CalendarDate(year: thursday.year, month: 1, day: 1)
        return jan1.days(until: thursday) / 7 + 1
    }

    public var iso8601: String {
        "\(year)-\(Self.pad(month))-\(Self.pad(day))"
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
