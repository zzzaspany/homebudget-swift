import Fluent
import HomeBudgetCore
import Vapor

final class PaymentModel: Model, @unchecked Sendable {
    static let schema = "payments"

    @ID(key: .id) var id: UUID?
    @Parent(key: "expense_id") var expense: ExpenseModel
    @Field(key: "amount_paid") var amountPaid: Double
    @Field(key: "date_paid") var datePaid: Date
    @Field(key: "period") var period: String
    @Field(key: "paid_by") var paidBy: String
    @OptionalField(key: "invoice_filename") var invoiceFilename: String?
    @OptionalField(key: "invoice_storage_path") var invoiceStoragePath: String?
    @OptionalField(key: "invoice_content_type") var invoiceContentType: String?
    @OptionalField(key: "invoice_size_bytes") var invoiceSizeBytes: Int?
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?

    init() {}

    init(
        id: UUID? = nil, expenseID: UUID, amountPaid: Double, datePaid: Date, period: String,
        paidBy: String, invoiceFilename: String? = nil, invoiceStoragePath: String? = nil,
        invoiceContentType: String? = nil, invoiceSizeBytes: Int? = nil
    ) {
        self.id = id
        self.$expense.id = expenseID
        self.amountPaid = amountPaid
        self.datePaid = datePaid
        self.period = period
        self.paidBy = paidBy
        self.invoiceFilename = invoiceFilename
        self.invoiceStoragePath = invoiceStoragePath
        self.invoiceContentType = invoiceContentType
        self.invoiceSizeBytes = invoiceSizeBytes
    }

    /// Requires the `expense` relation to be loaded.
    func record() throws -> PaymentRecord {
        PaymentRecord(
            id: try requireID().uuidString,
            expenseID: $expense.id.uuidString,
            expenseName: expense.name,
            category: expense.category,
            amountPaid: amountPaid,
            datePaid: CalendarDate(utc: datePaid),
            period: period,
            paidBy: paidBy,
            hasInvoice: invoiceStoragePath != nil
        )
    }

    var domain: Payment {
        Payment(
            id: id?.uuidString ?? "",
            expenseID: $expense.id.uuidString,
            amountPaid: amountPaid,
            datePaid: CalendarDate(utc: datePaid),
            period: period,
            paidBy: paidBy,
            invoiceFilename: invoiceFilename
        )
    }
}

extension CalendarDate {
    /// Calendar days are stored and read in UTC so the value never shifts with the server's timezone.
    init(utc date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    var utcDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
    }

    static func today() -> CalendarDate {
        CalendarDate(utc: Date())
    }
}
