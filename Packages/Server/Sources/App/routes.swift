import Vapor

func routes(_ app: Application) throws {
    let authenticated = app.grouped(AuthHeaderMiddleware())

    authenticated.get { request async throws -> View in
        let user = try request.auth.require(UserProfile.self)
        return try await request.view.render(
            "dashboard",
            [
                "userName": user.name,
                "userEmail": user.email,
                "userInitial": String(user.name.prefix(1)).uppercased(),
                "devMode": request.devMode ? "true" : "",
            ]
        )
    }

    app.get("health") { _ in "ok" }

    try authenticated.register(collection: ExpensesController())
    try authenticated.register(collection: PaymentsController())
    try authenticated.register(collection: ReportsController())
    try authenticated.register(collection: NotificationsController())
}
