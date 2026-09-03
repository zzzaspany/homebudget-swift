public enum ExpenseStatus: String, Codable, CaseIterable, Sendable {
    case paid
    case overdue
    case dueSoon = "due_soon"
    case upcoming
    case inactive

    /// Whether this status should raise an alert on the dashboard.
    public var isAlerting: Bool {
        self == .overdue || self == .dueSoon
    }
}

public struct ExpenseStatusResult: Hashable, Sendable {
    public let status: ExpenseStatus
    public let dueDate: CalendarDate?
    public let daysLeft: Int?

    public init(status: ExpenseStatus, dueDate: CalendarDate?, daysLeft: Int?) {
        self.status = status
        self.dueDate = dueDate
        self.daysLeft = daysLeft
    }
}
