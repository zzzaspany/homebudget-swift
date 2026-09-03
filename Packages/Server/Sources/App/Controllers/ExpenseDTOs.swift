import HomeBudgetCore
import Vapor

struct CreateExpenseRequest: Content, Validatable {
    let name: String
    let amount: Double
    let frequency: Frequency
    let dueDay: Int
    let dueMonth: Int?
    let category: String
    let active: Bool?
    let isVariable: Bool?

    enum CodingKeys: String, CodingKey {
        case name, amount, frequency, category, active
        case dueDay = "due_day"
        case dueMonth = "due_month"
        case isVariable = "is_variable"
    }

    static func validations(_ validations: inout Validations) {
        validations.add("name", as: String.self, is: !.empty)
        validations.add("amount", as: Double.self, is: .range(0.01...))
        validations.add("due_day", as: Int.self, is: .range(1...31))
        validations.add("category", as: String.self, is: !.empty)
        validations.add("due_month", as: Int?.self, is: .nil || .range(1...12), required: false)
    }
}

struct UpdateExpenseRequest: Content {
    let name: String?
    let amount: Double?
    let frequency: Frequency?
    let dueDay: Int?
    let dueMonth: Int?
    let category: String?
    let active: Bool?
    let isVariable: Bool?

    enum CodingKeys: String, CodingKey {
        case name, amount, frequency, category, active
        case dueDay = "due_day"
        case dueMonth = "due_month"
        case isVariable = "is_variable"
    }
}

struct PayExpenseRequest: Content {
    let amountPaid: Double?
    let invoiceFile: File?

    enum CodingKeys: String, CodingKey {
        case amountPaid = "amount_paid"
        case invoiceFile = "invoice_file"
    }
}

extension PaymentRecord: @retroactive Content {}
