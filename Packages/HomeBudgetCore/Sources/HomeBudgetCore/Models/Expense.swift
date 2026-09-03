public struct Expense: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var amount: Double
    public var frequency: Frequency
    public var dueDay: Int
    public var dueMonth: Int?
    public var category: String
    /// Opaque period marker whose format depends on `frequency` — see `PeriodKey`.
    public var lastPaidPeriod: String
    public var active: Bool
    public var isVariable: Bool

    public init(
        id: String,
        name: String,
        amount: Double,
        frequency: Frequency,
        dueDay: Int,
        dueMonth: Int? = nil,
        category: String,
        lastPaidPeriod: String = "",
        active: Bool = true,
        isVariable: Bool = false
    ) {
        self.id = id
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.dueDay = dueDay
        self.dueMonth = dueMonth
        self.category = category
        self.lastPaidPeriod = lastPaidPeriod
        self.active = active
        self.isVariable = isVariable
    }

    enum CodingKeys: String, CodingKey {
        case id, name, amount, frequency, category, active
        case dueDay = "due_day"
        case dueMonth = "due_month"
        case lastPaidPeriod = "last_paid_period"
        case isVariable = "is_variable"
    }

    /// Cycle anchor month, defaulting to January when unset — matches the Python app's `due_month or 1`.
    var anchorMonth: Int {
        guard let dueMonth, dueMonth >= 1, dueMonth <= 12 else { return 1 }
        return dueMonth
    }

    public var proratedMonthlyAmount: Double {
        frequency.proratedMonthlyAmount(of: amount)
    }
}

public struct Payment: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public var expenseID: String
    public var amountPaid: Double
    public var datePaid: CalendarDate
    public var period: String
    public var paidBy: String
    public var invoiceFilename: String?

    public init(
        id: String,
        expenseID: String,
        amountPaid: Double,
        datePaid: CalendarDate,
        period: String,
        paidBy: String,
        invoiceFilename: String? = nil
    ) {
        self.id = id
        self.expenseID = expenseID
        self.amountPaid = amountPaid
        self.datePaid = datePaid
        self.period = period
        self.paidBy = paidBy
        self.invoiceFilename = invoiceFilename
    }

    enum CodingKeys: String, CodingKey {
        case id, period
        case expenseID = "expense_id"
        case amountPaid = "amount_paid"
        case datePaid = "date_paid"
        case paidBy = "paid_by"
        case invoiceFilename = "invoice_filename"
    }
}
