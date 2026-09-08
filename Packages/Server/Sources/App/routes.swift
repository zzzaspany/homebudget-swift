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

    // Reports the running version as well as liveness, so "what is actually deployed" has an
    // answer that does not involve reading image tags. Unauthenticated, like the rest of the
    // health check — the version of a household budget app is not a secret, and a monitor that has
    // to sign in first is a monitor that reports on the sign-in.
    app.get("health") { _ in
        HealthResponse(status: "ok", version: Environment.get("APP_VERSION") ?? "dev")
    }

    try authenticated.register(collection: ExpensesController())
    try authenticated.register(collection: PaymentsController())
    try authenticated.register(collection: ReportsController())
    try authenticated.register(collection: NotificationsController())
    try authenticated.register(collection: IdentityController())
}


/// What `/health` answers with.
struct HealthResponse: Content {
    let status: String
    let version: String
}
