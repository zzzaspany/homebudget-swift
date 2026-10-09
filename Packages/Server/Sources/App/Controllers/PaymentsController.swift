import Fluent
import HomeBudgetCore
import Vapor

struct PaymentsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let payments = routes.grouped("api", "payments")
        payments.get(use: list)
        payments.put(":paymentID", use: update)
        payments.get(":paymentID", "invoice", use: invoice)
    }

    func list(request: Request) async throws -> [PaymentRecord] {
        let payments = try await PaymentModel.query(on: request.db)
            .with(\.$expense)
            .sort(\.$createdAt, .descending)
            .all()

        return try payments.map { try $0.record() }
    }

    /// Corrects a payment's date or amount. The period it settles is left alone: that was decided
    /// when the bill was paid, and moving it would quietly change which bills count as paid.
    func update(request: Request) async throws -> PaymentRecord {
        guard let id = request.parameters.get("paymentID", as: UUID.self),
            let payment = try await PaymentModel.query(on: request.db)
                .filter(\.$id == id)
                .with(\.$expense)
                .first()
        else {
            throw Abort(.notFound, reason: "Payment not found")
        }
        let input = try request.content.decode(UpdatePaymentRequest.self)

        if let amount = input.amountPaid {
            guard amount > 0 else { throw Abort(.badRequest, reason: "Amount must be positive") }
            payment.amountPaid = amount
        }
        if let text = input.datePaid {
            guard let date = CalendarDate(iso8601: text) else {
                throw Abort(.badRequest, reason: "date_paid must be YYYY-MM-DD")
            }
            guard date <= .today() else {
                throw Abort(.badRequest, reason: "A payment date cannot be in the future")
            }
            payment.datePaid = date.utcDate
        }

        try await payment.save(on: request.db)
        return try payment.record()
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
