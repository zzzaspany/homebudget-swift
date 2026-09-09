import Vapor

/// The signed-in user, as reported by the reverse proxy in front of the app.
struct UserProfile: Authenticatable, Content {
    let username: String
    let name: String
    let email: String
}

extension Application {
    private struct DevModeKey: StorageKey {
        typealias Value = Bool
    }

    /// Serves a fixed local user instead of requiring identity headers.
    ///
    /// Held on the application rather than read from the process environment on each request, so
    /// tests can set it per instance instead of mutating global state.
    var devMode: Bool {
        get { storage[DevModeKey.self] ?? false }
        set { storage[DevModeKey.self] = newValue }
    }
}

extension Request {
    var devMode: Bool { application.devMode }
}

/// Establishes who is calling, from one of two sources.
///
/// A **person** arrives through Authelia, which sets identity headers on the way past. A **machine**
/// arrives with an API token and gets read-only access — no sign-in page is usable from a shortcut
/// or a cron job, and nothing that reads a household budget needs to write to it.
///
/// The header path trusts whatever the caller sends, so the app must never be reachable except
/// through the proxy. That is a deployment property this code cannot enforce, and it is currently
/// not true — see `docs/deployment.md`.
struct AuthHeaderMiddleware: AsyncMiddleware {
    static let usernameHeaders = ["Remote-User", "X-Forwarded-User", "X-Auth-User"]
    static let nameHeaders = ["Remote-Name", "X-Forwarded-Name", "X-Auth-Name"]
    static let emailHeaders = ["Remote-Email", "X-Forwarded-Email", "X-Auth-Email"]

    /// The methods a token may use. Enforced here rather than by registering a second, read-only
    /// route table, so a write endpoint added later is closed to tokens the moment it exists rather
    /// than whenever somebody remembers to close it.
    static let readOnlyMethods: [HTTPMethod] = [.GET, .HEAD]

    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        if let presented = APIToken.presented(in: request) {
            // A token that is offered and wrong is refused outright. Falling through to the header
            // path would make presenting a bad token a way to *lower* the bar, not raise it.
            guard let token = APIToken.match(secret: presented, in: request.application.apiTokens)
            else {
                throw Abort(.unauthorized, reason: "Unknown API token")
            }
            guard Self.readOnlyMethods.contains(request.method) else {
                throw Abort(.forbidden, reason: "API tokens are read-only")
            }

            request.auth.login(
                UserProfile(
                    username: token.name, name: token.name,
                    email: "\(token.name)@api.localhost"))
            return try await next.respond(to: request)
        }

        request.auth.login(try profile(for: request))
        return try await next.respond(to: request)
    }

    private func profile(for request: Request) throws -> UserProfile {
        let username = Self.usernameHeaders.lazy.compactMap { request.headers.first(name: $0) }.first

        guard let username, !username.isEmpty else {
            guard request.devMode else {
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
