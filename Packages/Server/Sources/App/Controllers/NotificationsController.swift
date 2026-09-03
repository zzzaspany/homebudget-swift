import Fluent
import HomeBudgetCore
import Vapor

struct NotificationsController: RouteCollection {
    struct Result: Content {
        let success: Bool
        let message: String
        let alertCount: Int
    }

    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("api", "notifications").post("send-email", use: sendEmail)
    }

    func sendEmail(request: Request) async throws -> Result {
        let language = Language(code: request.query[String.self, at: "lang"])
        let expenses = try await ExpenseModel.query(on: request.db).sort(\.$name).all()
        let dashboard = DashboardBuilder.build(expenses: expenses.map(\.domain), today: .today())
        let notifications = dashboard.notifications

        guard !notifications.isEmpty else {
            return Result(
                success: true,
                message: language == .pl
                    ? "Nic nie wymaga uwagi — e-mail nie został wysłany."
                    : "Nothing needs attention — no e-mail sent.",
                alertCount: 0
            )
        }

        let configuration = try SMTPConfiguration.fromEnvironment()
        let message = EmailMessage(
            from: configuration.sender,
            to: [configuration.recipient],
            subject: AlertEmail.subject(alertCount: notifications.count, language: language),
            htmlBody: AlertEmail.html(notifications: notifications, language: language)
        )

        do {
            try await SMTPClient(configuration: configuration, logger: request.logger)
                .send(message, on: request.eventLoop)
        } catch {
            request.logger.error("Payment reminder failed: \(error)")
            throw Abort(.badGateway, reason: String(describing: error))
        }

        return Result(
            success: true,
            message: language == .pl
                ? "Wysłano powiadomienie z \(Localization.alertCountLabel(notifications.count, language: .pl))."
                : "Sent a notification with \(notifications.count) alert\(notifications.count == 1 ? "" : "s").",
            alertCount: notifications.count
        )
    }
}
