import Fluent
import HomeBudgetCore
import Vapor

final class ExpenseModel: Model, @unchecked Sendable {
    static let schema = "expenses"

    @ID(key: .id) var id: UUID?
    @Field(key: "name") var name: String
    @Field(key: "amount") var amount: Double
    @Enum(key: "frequency") var frequency: Frequency
    @Field(key: "due_day") var dueDay: Int
    @OptionalField(key: "due_month") var dueMonth: Int?
    @Field(key: "category") var category: String
    @Field(key: "last_paid_period") var lastPaidPeriod: String
    @Field(key: "active") var active: Bool
    @Field(key: "is_variable") var isVariable: Bool
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    @Children(for: \.$expense) var payments: [PaymentModel]

    init() {}

    init(
        id: UUID? = nil, name: String, amount: Double, frequency: Frequency, dueDay: Int,
        dueMonth: Int?, category: String, lastPaidPeriod: String = "", active: Bool = true,
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

    /// The domain-layer value used by every calculation in `HomeBudgetCore`.
    var domain: Expense {
        Expense(
            id: id?.uuidString ?? "",
            name: name,
            amount: amount,
            frequency: frequency,
            dueDay: dueDay,
            dueMonth: dueMonth,
            category: category,
            lastPaidPeriod: lastPaidPeriod,
            active: active,
            isVariable: isVariable
        )
    }
}
