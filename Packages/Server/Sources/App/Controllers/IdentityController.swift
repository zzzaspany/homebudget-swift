import HomeBudgetCore
import Vapor

/// Reports who the reverse proxy says is making the request.
///
/// The web client reads its user from the page the server renders. A native client has no such
/// page, so it asks — and uses the answer to tell a live session from an expired one, since
/// Authelia answers an expired session with a redirect rather than a 401.
struct IdentityController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        routes.grouped("api").get("whoami", use: whoami)
    }

    func whoami(request: Request) async throws -> UserProfile {
        try request.auth.require(UserProfile.self)
    }
}
