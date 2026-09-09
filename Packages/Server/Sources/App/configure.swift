import Fluent
import FluentPostgresDriver
import Leaf
import Vapor

public func configure(_ app: Application) async throws {
    app.devMode = Environment.get("DEV_MODE")?.lowercased() == "true"
    app.apiTokens = APIToken.parse(Environment.get("API_TOKENS") ?? "") {
        app.logger.warning("Ignoring an API_TOKENS entry: \($0)")
    }
    if !app.apiTokens.isEmpty {
        app.logger.info(
            "Read-only API tokens accepted for: \(app.apiTokens.map(\.name).joined(separator: ", "))")
    }

    app.databases.use(.postgres(configuration: try postgresConfiguration()), as: .psql)

    app.migrations.add(CreateFrequencyEnum())
    app.migrations.add(CreateExpense())
    app.migrations.add(CreatePayment())

    app.views.use(.leaf)
    app.middleware.use(FileMiddleware(publicDirectory: app.directory.publicDirectory))

    if let port = Environment.get("PORT").flatMap(Int.init) {
        app.http.server.configuration.port = port
    }

    try routes(app)
}

private func postgresConfiguration() throws -> SQLPostgresConfiguration {
    if let url = Environment.get("DATABASE_URL") {
        return try SQLPostgresConfiguration(url: url)
    }

    return SQLPostgresConfiguration(
        hostname: Environment.get("POSTGRES_HOST") ?? "localhost",
        port: Environment.get("POSTGRES_PORT").flatMap(Int.init)
            ?? SQLPostgresConfiguration.ianaPortNumber,
        username: Environment.get("POSTGRES_USER") ?? "homebudget",
        password: Environment.get("POSTGRES_PASSWORD"),
        database: Environment.get("POSTGRES_DB") ?? "homebudget",
        tls: .disable
    )
}
