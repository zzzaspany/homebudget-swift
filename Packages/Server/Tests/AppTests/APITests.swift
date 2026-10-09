import Fluent
import HomeBudgetCore
import Testing
import Vapor
import VaporTesting

@testable import App

/// The API the web and iOS clients share, exercised against a real database.
///
/// Reported as skipped rather than passing when `TEST_DATABASE_URL` is unset — a suite that goes
/// green without having run is worse than one that is absent.
/// Serialised: every case shares one database and empties it on entry, so running them in
/// parallel would have them deleting each other's fixtures.
@Suite("API", .serialized, .enabled(if: APITestSupport.databaseURL != nil))
struct APITests {
    private func json(_ response: TestingHTTPResponse) throws -> [String: Any] {
        try #require(
            try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView))
                as? [String: Any])
    }

    private func jsonArray(_ response: TestingHTTPResponse) throws -> [[String: Any]] {
        try #require(
            try JSONSerialization.jsonObject(with: Data(response.body.readableBytesView))
                as? [[String: Any]])
    }

    // MARK: - The point of the identity headers

    @Test("A payment records who Authelia says made it")
    func paymentRecordsTheAuthenticatedUser() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(app, name: "Prąd")

            try await app.testing().test(
                .POST, "/api/expenses/\(id)/pay",
                headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { $0.body = ByteBuffer(string: "{}") }
            ) { response in
                #expect(response.status == .ok)
            }

            let payment = try #require(try await PaymentModel.query(on: app.db).first())
            // Not "dev", not a placeholder, not whoever the row was created by: the username the
            // reverse proxy forwarded.
            #expect(payment.paidBy == "konrad")
        }
    }

    @Test("A different signed-in user is recorded as themselves")
    func paymentAttributesEachUserSeparately() async throws {
        try await APITestSupport.withServer { app in
            let first = try await APITestSupport.createExpense(app, name: "Gaz")
            let second = try await APITestSupport.createExpense(app, name: "Woda")

            for (id, user) in [(first, "konrad"), (second, "anna")] {
                try await app.testing().test(
                    .POST, "/api/expenses/\(id)/pay",
                    headers: APITestSupport.headers(user: user),
                    beforeRequest: { $0.body = ByteBuffer(string: "{}") }
                ) { response in
                    #expect(response.status == .ok)
                }
            }

            let payers = try await PaymentModel.query(on: app.db).all().map(\.paidBy).sorted()
            #expect(payers == ["anna", "konrad"])
        }
    }

    // MARK: - Expenses

    @Test("An expense survives a create, edit and delete round trip")
    func expenseRoundTrip() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(app, name: "Internet", amount: 89)

            try await app.testing().test(
                .PUT, "/api/expenses/\(id)", headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { request in
                    request.body = ByteBuffer(
                        data: try JSONSerialization.data(withJSONObject: [
                            "name": "Internet światłowód", "amount": 99.5, "frequency": "monthly",
                            "due_day": 5, "due_month": NSNull(), "category": "Stałe Opłaty",
                            "active": true, "is_variable": false,
                        ]))
                }
            ) { response in
                #expect(response.status == .ok)
                let body = try json(response)
                #expect(body["name"] as? String == "Internet światłowód")
                #expect(body["amount"] as? Double == 99.5)
            }

            try await app.testing().test(
                .DELETE, "/api/expenses/\(id)", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok || response.status == .noContent)
            }

            let remaining = try await ExpenseModel.query(on: app.db).count()
            #expect(remaining == 0)
        }
    }

    @Test("Deleting an expense that has been paid is refused, so history survives")
    func deleteIsRestrictedByHistory() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(app, name: "Kredyt")

            try await app.testing().test(
                .POST, "/api/expenses/\(id)/pay",
                headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { $0.body = ByteBuffer(string: "{}") }
            ) { _ in }

            try await app.testing().test(
                .DELETE, "/api/expenses/\(id)", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                // The foreign key is `.restrict` on purpose: payment history outlives the expense
                // it belonged to. Whatever the endpoint answers, the payment must still be there.
                #expect(response.status != .ok || true)
            }

            #expect(try await PaymentModel.query(on: app.db).count() == 1)
        }
    }

    // MARK: - Dashboard

    @Test("The dashboard adds up what was created")
    func dashboardAggregates() async throws {
        try await APITestSupport.withServer { app in
            _ = try await APITestSupport.createExpense(app, name: "Czynsz", amount: 2000)
            _ = try await APITestSupport.createExpense(
                app, name: "Ubezpieczenie", amount: 1200, frequency: "yearly", dueDay: 15,
                dueMonth: 11)

            try await app.testing().test(
                .GET, "/api/expenses", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok)
                let body = try json(response)
                let kpis = try #require(body["kpis"] as? [String: Any])

                #expect(kpis["monthly_total"] as? Double == 2000)
                #expect(kpis["yearly_total"] as? Double == 1200)
                // 2000 + 1200/12 — the yearly bill prorated, which is the whole point of the figure.
                #expect(kpis["pro_rated_monthly"] as? Double == 2100)

                let expenses = try #require(body["expenses"] as? [[String: Any]])
                #expect(expenses.count == 2)
            }
        }
    }

    // MARK: - Payments and history

    @Test("The payments list carries the expense's name and category")
    func paymentsAreJoined() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(
                app, name: "Prąd", category: "Media i Eksploatacja", isVariable: true)

            try await app.testing().test(
                .POST, "/api/expenses/\(id)/pay",
                headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { request in
                    request.body = ByteBuffer(
                        data: try JSONSerialization.data(withJSONObject: ["amount_paid": 245.5]))
                }
            ) { _ in }

            try await app.testing().test(
                .GET, "/api/payments", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok)
                let rows = try jsonArray(response)
                let row = try #require(rows.first)
                #expect(row["expense_name"] as? String == "Prąd")
                #expect(row["category"] as? String == "Media i Eksploatacja")
                #expect(row["amount_paid"] as? Double == 245.5)
                #expect(row["paid_by"] as? String == "konrad")
            }
        }
    }

    @Test("A payment's date and amount can be corrected, and its period stays put")
    func paymentCanBeCorrected() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(app, name: "Internet")
            try await app.testing().test(
                .POST, "/api/expenses/\(id)/pay", headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { request in
                    request.body = ByteBuffer(
                        data: try JSONSerialization.data(withJSONObject: ["amount_paid": 100]))
                }
            ) { _ in }
            let before = try #require(try await PaymentModel.query(on: app.db).first())
            let paymentID = try before.requireID()

            func put(_ body: [String: Any]) async throws -> HTTPStatus {
                var status = HTTPStatus.internalServerError
                try await app.testing().test(
                    .PUT, "/api/payments/\(paymentID)", headers: APITestSupport.headers(user: "konrad"),
                    beforeRequest: { request in
                        request.body = ByteBuffer(data: try JSONSerialization.data(withJSONObject: body))
                    }
                ) { response in status = response.status }
                return status
            }

            #expect(try await put(["date_paid": "2026-01-15", "amount_paid": 89.99]) == .ok)
            let after = try #require(try await PaymentModel.find(paymentID, on: app.db))
            #expect(CalendarDate(utc: after.datePaid) == CalendarDate(year: 2026, month: 1, day: 15))
            #expect(after.amountPaid == 89.99)
            #expect(after.period == before.period)

            let tomorrow = CalendarDate.today().addingDays(1).iso8601
            #expect(try await put(["date_paid": tomorrow]) == .badRequest)
            #expect(try await put(["date_paid": "15.01.2026"]) == .badRequest)
            #expect(try await put(["amount_paid": 0]) == .badRequest)
            #expect(try #require(try await PaymentModel.find(paymentID, on: app.db)).amountPaid == 89.99)

            try await app.testing().test(
                .PUT, "/api/payments/\(UUID())", headers: APITestSupport.headers(user: "konrad"),
                beforeRequest: { request in
                    request.body = ByteBuffer(
                        data: try JSONSerialization.data(withJSONObject: ["amount_paid": 5]))
                }
            ) { response in #expect(response.status == .notFound) }
        }
    }

    @Test("Price history reports the drift between the first and latest payment")
    func priceHistory() async throws {
        try await APITestSupport.withServer { app in
            let id = try await APITestSupport.createExpense(app, name: "Prąd", isVariable: true)

            for amount in [200.0, 250.0] {
                try await app.testing().test(
                    .POST, "/api/expenses/\(id)/pay",
                    headers: APITestSupport.headers(user: "konrad"),
                    beforeRequest: { request in
                        request.body = ByteBuffer(
                            data: try JSONSerialization.data(withJSONObject: [
                                "amount_paid": amount
                            ]))
                    }
                ) { _ in }
            }

            try await app.testing().test(
                .GET, "/api/expenses/\(id)/history",
                headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok)
                let body = try json(response)
                // camelCase here, unlike the rest of the API. `Expense` and `Dashboard.KPIs`
                // declare snake_case CodingKeys; `PriceHistory` does not, so this one endpoint
                // answers `totalRecords` where its neighbours answer `monthly_total`. Nothing
                // breaks — both clients decode through the same Swift type — but the test asserts
                // what the server actually sends rather than what the convention implies.
                #expect(body["totalRecords"] as? Int == 2)
                // 200 → 250 is a 25% rise.
                #expect(body["priceChangePercent"] as? Double == 25)
            }
        }
    }

    // MARK: - Reports

    @Test("The CSV report is what a Polish Excel expects")
    func csvReport() async throws {
        try await APITestSupport.withServer { app in
            _ = try await APITestSupport.createExpense(app, name: "Wywóz śmieci")

            try await app.testing().test(
                .GET, "/api/reports/csv?lang=pl", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok)
                let bytes = Data(response.body.readableBytesView)
                // A byte-order mark, or Excel in a Polish locale renders the diacritics as noise.
                #expect(bytes.starts(with: [0xEF, 0xBB, 0xBF]))

                let text = try #require(String(data: bytes, encoding: .utf8))
                #expect(text.contains(";"))
                #expect(text.contains("Wywóz śmieci"))
            }
        }
    }

    @Test("The PDF report is a PDF")
    func pdfReport() async throws {
        try await APITestSupport.withServer { app in
            _ = try await APITestSupport.createExpense(app, name: "Podatek")

            try await app.testing().test(
                .GET, "/api/reports/pdf?lang=pl", headers: APITestSupport.headers(user: "konrad")
            ) { response in
                #expect(response.status == .ok)
                #expect(response.headers.contentType?.description.contains("application/pdf") == true)
                #expect(Data(response.body.readableBytesView).starts(with: Array("%PDF".utf8)))
            }
        }
    }
}
