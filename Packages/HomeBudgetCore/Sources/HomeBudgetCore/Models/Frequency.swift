public enum Frequency: String, Codable, CaseIterable, Sendable {
    case monthly
    case biweekly
    case quarterly
    case semiAnnual = "semi_annual"
    case yearly

    /// Share of this expense that has to be set aside each month.
    public func proratedMonthlyAmount(of amount: Double) -> Double {
        switch self {
        case .monthly: return amount
        case .biweekly: return amount * 26.0 / 12.0
        case .quarterly: return amount / 3.0
        case .semiAnnual: return amount / 6.0
        case .yearly: return amount / 12.0
        }
    }

    /// Cycles longer than a month must say which month they fall in.
    public var requiresDueMonth: Bool {
        self == .yearly || self == .quarterly || self == .semiAnnual
    }

    /// Whether the expense is paid less often than monthly and therefore needs a savings reserve.
    public var needsSinkingFund: Bool {
        self != .monthly
    }

    /// Days before the due date at which an expense starts being reported as "due soon".
    public var dueSoonThresholdDays: Int {
        switch self {
        case .monthly: return 5
        case .biweekly: return 3
        case .quarterly: return 7
        case .semiAnnual: return 10
        case .yearly: return 14
        }
    }

    /// How often this repeats, in a form a calendar or reminder store can be told about.
    ///
    /// Kept here rather than in the iOS app so the mapping is testable without EventKit, and so a
    /// future export from the web client says the same thing.
    public var recurrenceInterval: RecurrenceInterval {
        switch self {
        case .monthly: return .months(1)
        case .biweekly: return .weeks(2)
        case .quarterly: return .months(3)
        case .semiAnnual: return .months(6)
        case .yearly: return .months(12)
        }
    }

    /// Number of months between two occurrences, or nil for biweekly which is not month-aligned.
    var monthInterval: Int? {
        switch self {
        case .quarterly: return 3
        case .semiAnnual: return 6
        case .yearly: return 12
        case .monthly: return 1
        case .biweekly: return nil
        }
    }
}

/// The gap between two occurrences of a recurring expense.
///
/// Deliberately not `Foundation.DateComponents`: `HomeBudgetCore` stays Foundation-free, and the
/// two cases are all the domain has — nothing here repeats on, say, the second Tuesday.
public enum RecurrenceInterval: Hashable, Sendable {
    case weeks(Int)
    case months(Int)
}
