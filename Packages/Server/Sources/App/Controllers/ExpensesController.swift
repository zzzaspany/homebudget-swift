import Fluent
import HomeBudgetCore
import Vapor

struct ExpensesController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let expenses = routes.grouped("api", "expenses")
        expenses.get(use: dashboard)
        expenses.post(use: create)
        expenses.put(":expenseID", use: update)
        expenses.delete(":expenseID", use: delete)
        expenses.post(":expenseID", "pay", use: pay)
        expenses.get(":expenseID", "history", use: history)
    }

    func dashboard(request: Request) async throws -> Dashboard {
        let expenses = try await ExpenseModel.query(on: request.db).sort(\.$name).all()
        return DashboardBuilder.build(expenses: expenses.map(\.domain), today: .today())
    }

    func create(request: Request) async throws -> Response {
        try CreateExpenseRequest.validate(content: request)
        let input = try request.content.decode(CreateExpenseRequest.self)
        try validateDueMonth(input.frequency, dueMonth: input.dueMonth)

        let expense = ExpenseModel(
            name: input.name,
            amount: input.amount,
            frequency: input.frequency,
            dueDay: input.dueDay,
            dueMonth: input.dueMonth,
            category: input.category,
            active: input.active ?? true,
            isVariable: input.isVariable ?? false
        )
        try await expense.save(on: request.db)

        return try await expense.domain.encodeResponse(status: .created, for: request)
    }

    func update(request: Request) async throws -> Expense {
        let expense = try await find(request)
        let input = try request.content.decode(UpdateExpenseRequest.self)

        if let name = input.name { expense.name = name }
        if let amount = input.amount { expense.amount = amount }
        if let frequency = input.frequency { expense.frequency = frequency }
        if let dueDay = input.dueDay { expense.dueDay = dueDay }
        if let dueMonth = input.dueMonth { expense.dueMonth = dueMonth }
        if let category = input.category { expense.category = category }
        if let active = input.active { expense.active = active }
        if let isVariable = input.isVariable { expense.isVariable = isVariable }

        guard expense.amount > 0, (1...31).contains(expense.dueDay), !expense.name.isEmpty,
            !expense.category.isEmpty
        else {
            throw Abort(.badRequest, reason: "Invalid expense values")
        }
        try validateDueMonth(expense.frequency, dueMonth: expense.dueMonth)

        try await expense.save(on: request.db)
        return expense.domain
    }

    func delete(request: Request) async throws -> HTTPStatus {
        let expense = try await find(request)
        do {
            try await expense.delete(on: request.db)
        } catch {
            // The payments foreign key is restricted, so an expense with history cannot be removed.
            throw Abort(.conflict, reason: "Expense has recorded payments and cannot be deleted")
        }
        return .noContent
    }

    func pay(request: Request) async throws -> Expense {
        let expense = try await find(request)
        let expenseID = try expense.requireID()
        let user = try request.auth.require(UserProfile.self)
        let input = try request.content.decode(PayExpenseRequest.self)

        let today = CalendarDate.today()
        let period = StatusCalculator.targetPeriod(for: expense.domain, today: today)

        let payment = PaymentModel(
            expenseID: expenseID,
            amountPaid: input.amountPaid ?? expense.amount,
            datePaid: today.utcDate,
            period: period,
            paidBy: user.username
        )

        if let file = input.invoiceFile, !file.filename.isEmpty {
            let paymentID = UUID()
            payment.id = paymentID
            payment.invoiceStoragePath = try await request.invoiceStorage.store(
                file, expenseID: expenseID, paymentID: paymentID, on: request)
            payment.invoiceFilename = file.filename
            payment.invoiceContentType = file.contentType?.serialize()
            payment.invoiceSizeBytes = file.data.readableBytes
        }

        try await payment.save(on: request.db)

        expense.lastPaidPeriod = period
        try await expense.save(on: request.db)

        return expense.domain
    }

    func history(request: Request) async throws -> PriceHistory {
        let expense = try await find(request)
        let expenseID = try expense.requireID()
        let payments = try await PaymentModel.query(on: request.db)
            .filter(\.$expense.$id == expenseID)
            .all()

        return PriceHistory.build(expenseID: expenseID.uuidString, payments: payments.map(\.domain))
    }

    private func find(_ request: Request) async throws -> ExpenseModel {
        guard let id = request.parameters.get("expenseID", as: UUID.self),
            let expense = try await ExpenseModel.find(id, on: request.db)
        else {
            throw Abort(.notFound, reason: "Expense not found")
        }
        return expense
    }

    private func validateDueMonth(_ frequency: Frequency, dueMonth: Int?) throws {
        guard frequency.requiresDueMonth else { return }
        guard let dueMonth, (1...12).contains(dueMonth) else {
            throw Abort(.badRequest, reason: "\(frequency.rawValue) expenses require a due month")
        }
    }
}

extension Dashboard: @retroactive Content {}
extension Expense: @retroactive Content {}
extension PriceHistory: @retroactive Content {}
