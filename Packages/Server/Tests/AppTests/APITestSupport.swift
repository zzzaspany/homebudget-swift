import Fluent
import FluentPostgresDriver
import Testing
import Vapor
import VaporTesting

@testable import App

/// A server wired to a throwaway database, for the tests that need one.
///
/// **These tests read `TEST_DATABASE_URL` and never `DATABASE_URL`.** That is not fussiness: the
/// repository's own `.env` points `DATABASE_URL` at the live household database, and a suite that
/// truncated tables would take the real payment history with it. An unset `TEST_DATABASE_URL` skips
/// the suite rather than falling back to anything.
enum APITestSupport {
    static var databaseURL: String? {
        Environment.get("TEST_DATABASE_URL")
    }

    /// Builds an application against the test database, migrates it, and empties the tables.
    ///
    /// Truncating rather than re-migrating between tests: migrations are the slow part, and the
    /// schema does not change between cases.
    static func withServer(
        devMode: Bool = false, _ body: (Application) async throws -> Void
    ) async throws {
        guard let url = databaseURL else { return }

        let app = try await Application.make(.testing)
        do {
            app.devMode = devMode
            app.databases.use(.postgres(configuration: try SQLPostgresConfiguration(url: url)), as: .psql)

            app.migrations.add(CreateFrequencyEnum())
            app.migrations.add(CreateExpense())
            app.migrations.add(CreatePayment())
            app.views.use(.leaf)
            app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))
            try routes(app)

            try await app.autoMigrate()
            // Payments first: the foreign key onto expenses is `.restrict`, deliberately, so that
            // deleting an expense cannot silently take its history with it.
            try await PaymentModel.query(on: app.db).delete()
            try await ExpenseModel.query(on: app.db).delete()

            try await body(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    /// Identity headers as the reverse proxy would set them after Authelia signs somebody in.
    static func headers(user: String) -> HTTPHeaders {
        var headers = HTTPHeaders()
        headers.add(name: "X-Forwarded-User", value: user)
        headers.add(name: "Content-Type", value: "application/json")
        return headers
    }

    /// Creates an expense through the API and returns its identifier.
    static func createExpense(
        _ app: Application, name: String, amount: Double = 100, frequency: String = "monthly",
        dueDay: Int = 10, dueMonth: Int? = nil, category: String = "Inne",
        isVariable: Bool = false, user: String = "tester"
    ) async throws -> String {
        var body: [String: Any] = [
            "name": name, "amount": amount, "frequency": frequency, "due_day": dueDay,
            "category": category, "active": true, "is_variable": isVariable,
        ]
        body["due_month"] = dueMonth as Any? ?? NSNull()

        var created: String?
        try await app.testing().test(
            .POST, "/api/expenses", headers: headers(user: user),
            beforeRequest: { request in
                request.body = ByteBuffer(
                    data: try JSONSerialization.data(withJSONObject: body))
            }
        ) { response in
            // Vapor answers a create with 201, which is right and worth asserting rather than
            // loosening to "not an error".
            #expect(response.status == .created)
            let json =
                try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView))
                as? [String: Any]
            created = json?["id"] as? String
        }
        return try #require(created)
    }
}
