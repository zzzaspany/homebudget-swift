/// A payment with its expense's name and category already resolved.
///
/// Shared by the payment history list, the CSV export and the PDF report so the join happens once.
public struct PaymentRecord: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let expenseID: String
    public let expenseName: String
    public let category: String
    public let amountPaid: Double
    public let datePaid: CalendarDate
    public let period: String
    public let paidBy: String
    public let hasInvoice: Bool

    public init(
        id: String,
        expenseID: String,
        expenseName: String,
        category: String,
        amountPaid: Double,
        datePaid: CalendarDate,
        period: String,
        paidBy: String,
        hasInvoice: Bool = false
    ) {
        self.id = id
        self.expenseID = expenseID
        self.expenseName = expenseName
        self.category = category
        self.amountPaid = amountPaid
        self.datePaid = datePaid
        self.period = period
        self.paidBy = paidBy
        self.hasInvoice = hasInvoice
    }

    enum CodingKeys: String, CodingKey {
        case id, category, period
        case expenseID = "expense_id"
        case expenseName = "expense_name"
        case amountPaid = "amount_paid"
        case datePaid = "date_paid"
        case paidBy = "paid_by"
        case hasInvoice = "has_invoice"
    }
}
