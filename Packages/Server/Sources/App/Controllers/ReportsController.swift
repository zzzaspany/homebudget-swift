import Fluent
import HomeBudgetCore
import Vapor

struct ReportsController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let reports = routes.grouped("api", "reports")
        reports.get("csv", use: csv)
    }

    func csv(request: Request) async throws -> Response {
        let language = Language(code: request.query[String.self, at: "lang"])
        let user = try request.auth.require(UserProfile.self)
        let (dashboard, payments) = try await load(on: request)

        let content = CSVReport.build(
            dashboard: dashboard,
            payments: payments,
            userName: user.name,
            generatedAt: .today(),
            language: language
        )

        var headers = HTTPHeaders()
        headers.contentType = HTTPMediaType(type: "text", subType: "csv", parameters: ["charset": "utf-8"])
        headers.contentDisposition = .init(.attachment, filename: "homebudget_raport.csv")

        return Response(status: .ok, headers: headers, body: .init(string: content))
    }

    /// The dashboard and the payment log, both of which every report is built from.
    func load(on request: Request) async throws -> (Dashboard, [PaymentRecord]) {
        let expenses = try await ExpenseModel.query(on: request.db).sort(\.$name).all()
        let payments = try await PaymentModel.query(on: request.db)
            .with(\.$expense)
            .sort(\.$createdAt, .descending)
            .all()

        let dashboard = DashboardBuilder.build(expenses: expenses.map(\.domain), today: .today())
        return (dashboard, try payments.map { try $0.record() })
    }
}
