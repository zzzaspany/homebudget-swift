import Fluent
import HomeBudgetCore

struct CreateFrequencyEnum: AsyncMigration {
    func prepare(on database: any Database) async throws {
        var builder = database.enum("frequency")
        for frequency in Frequency.allCases {
            builder = builder.case(frequency.rawValue)
        }
        _ = try await builder.create()
    }

    func revert(on database: any Database) async throws {
        try await database.enum("frequency").delete()
    }
}

struct CreateExpense: AsyncMigration {
    func prepare(on database: any Database) async throws {
        let frequency = try await database.enum("frequency").read()
        try await database.schema(ExpenseModel.schema)
            .id()
            .field("name", .string, .required)
            .field("amount", .double, .required)
            .field("frequency", frequency, .required)
            .field("due_day", .int, .required)
            .field("due_month", .int)
            .field("category", .string, .required)
            .field("last_paid_period", .string, .required, .sql(.default("")))
            .field("active", .bool, .required, .sql(.default(true)))
            .field("is_variable", .bool, .required, .sql(.default(false)))
            .field("created_at", .datetime)
            .field("updated_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(ExpenseModel.schema).delete()
    }
}

struct CreatePayment: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema(PaymentModel.schema)
            .id()
            // Restricted rather than cascading: payment history outlives the expense it belonged to.
            .field("expense_id", .uuid, .required, .references(ExpenseModel.schema, "id", onDelete: .restrict))
            .field("amount_paid", .double, .required)
            .field("date_paid", .date, .required)
            .field("period", .string, .required)
            .field("paid_by", .string, .required)
            .field("invoice_filename", .string)
            .field("invoice_storage_path", .string)
            .field("invoice_content_type", .string)
            .field("invoice_size_bytes", .int)
            .field("created_at", .datetime)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema(PaymentModel.schema).delete()
    }
}
