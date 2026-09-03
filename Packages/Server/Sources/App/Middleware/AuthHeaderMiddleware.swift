import Vapor

/// The signed-in user, as reported by the reverse proxy in front of the app.
struct UserProfile: Authenticatable, Content {
    let username: String
    let name: String
    let email: String
}

/// Trusts identity headers set by the reverse proxy (Authelia).
///
/// The app must never be exposed directly: anything that can reach it can set these headers.
/// `DEV_MODE=true` substitutes a fixed local user so the app runs without a proxy in front of it.
struct AuthHeaderMiddleware: AsyncMiddleware {
    static let usernameHeaders = ["Remote-User", "X-Forwarded-User", "X-Auth-User"]
    static let nameHeaders = ["Remote-Name", "X-Forwarded-Name", "X-Auth-Name"]
    static let emailHeaders = ["Remote-Email", "X-Forwarded-Email", "X-Auth-Email"]

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        request.auth.login(try profile(for: request))
        return try await next.respond(to: request)
    }

    private func profile(for request: Request) throws -> UserProfile {
        let username = Self.usernameHeaders.lazy.compactMap { request.headers.first(name: $0) }.first

        guard let username, !username.isEmpty else {
            guard Environment.get("DEV_MODE")?.lowercased() == "true" else {
                throw Abort(.unauthorized, reason: "Missing SSO authentication headers")
            }
            return UserProfile(username: "dev", name: "Developer", email: "dev@localhost")
        }

        let name = Self.nameHeaders.lazy.compactMap { request.headers.first(name: $0) }.first
        let email = Self.emailHeaders.lazy.compactMap { request.headers.first(name: $0) }.first

        return UserProfile(
            username: username,
            name: name ?? username,
            email: email ?? "\(username)@localhost"
        )
    }
}
