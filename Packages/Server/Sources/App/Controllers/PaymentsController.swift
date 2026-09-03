import Fluent
import HomeBudgetCore
import Vapor

struct PaymentsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let payments = routes.grouped("api", "payments")
        payments.get(use: list)
        payments.get(":paymentID", "invoice", use: invoice)
    }

    func list(request: Request) async throws -> [PaymentRecord] {
        let payments = try await PaymentModel.query(on: request.db)
            .with(\.$expense)
            .sort(\.$createdAt, .descending)
            .all()

        return try payments.map { payment in
            PaymentRecord(
                id: try payment.requireID().uuidString,
                expenseID: payment.$expense.id.uuidString,
                expenseName: payment.expense.name,
                category: payment.expense.category,
                amountPaid: payment.amountPaid,
                datePaid: CalendarDate(utc: payment.datePaid),
                period: payment.period,
                paidBy: payment.paidBy,
                hasInvoice: payment.invoiceStoragePath != nil
            )
        }
    }

    func invoice(request: Request) async throws -> Response {
        guard let id = request.parameters.get("paymentID", as: UUID.self),
            let payment = try await PaymentModel.find(id, on: request.db),
            let storagePath = payment.invoiceStoragePath
        else {
            throw Abort(.notFound, reason: "Invoice not found")
        }

        let response = try await request.fileio.asyncStreamFile(
            at: request.invoiceStorage.absolutePath(for: storagePath))
        if let filename = payment.invoiceFilename {
            response.headers.contentDisposition = .init(.attachment, filename: filename)
        }
        return response
    }
}
