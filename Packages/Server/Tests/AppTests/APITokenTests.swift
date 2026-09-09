import Testing
import Vapor
import VaporTesting

@testable import App

/// Parsing needs no database, so it is checked on its own rather than behind the suite's skip.
@Suite("API token parsing")
struct APITokenParsingTests {
    private static let good = String(repeating: "a", count: APIToken.minimumSecretLength)

    @Test("Reads name and secret from each comma-separated pair")
    func parsesPairs() {
        let tokens = APIToken.parse("shortcuts:\(Self.good),n8n:\(Self.good)b")
        #expect(tokens.map(\.name) == ["shortcuts", "n8n"])
        #expect(tokens.last?.secret == "\(Self.good)b")
    }

    @Test("Tolerates whitespace around entries")
    func trimsWhitespace() {
        let tokens = APIToken.parse(" shortcuts : \(Self.good) ")
        #expect(tokens.count == 1)
        #expect(tokens.first?.name == "shortcuts")
        #expect(tokens.first?.secret == Self.good)
    }

    @Test("A secret is allowed to contain colons")
    func secretKeepsColons() {
        let secret = "\(Self.good):tail"
        #expect(APIToken.parse("client:\(secret)").first?.secret == secret)
    }

    @Test("Drops the malformed entries and keeps the rest")
    func dropsMalformed() {
        var complaints: [String] = []
        let tokens = APIToken.parse(
            "nocolon,:\(Self.good),tooshort:abc,good:\(Self.good)", report: { complaints.append($0) })

        // One bad pair in the environment must not take the working clients offline with it.
        #expect(tokens.map(\.name) == ["good"])
        #expect(complaints.count == 3)
    }

    @Test("An empty setting is no tokens at all, not a default one")
    func emptyMeansDisabled() {
        #expect(APIToken.parse("").isEmpty)
        #expect(APIToken.parse("  ,  ").isEmpty)
    }

    @Test("Matches only the exact secret")
    func matching() {
        let tokens = APIToken.parse("a:\(Self.good)1,b:\(Self.good)2")
        #expect(APIToken.match(secret: "\(Self.good)2", in: tokens)?.name == "b")
        #expect(APIToken.match(secret: "\(Self.good)3", in: tokens) == nil)
        // A prefix of a valid secret is not a valid secret.
        #expect(APIToken.match(secret: Self.good, in: tokens) == nil)
        #expect(APIToken.match(secret: "", in: tokens) == nil)
    }
}

/// What a token can and cannot do against a running server.
///
/// Nested inside `APITests` rather than standing alone: `.serialized` orders the cases *within* a
/// suite, and these share one database with that suite and empty it on entry. As siblings the two
/// ran concurrently and deleted each other's fixtures. Nesting puts them under the same
/// serialisation.
extension APITests {
    @Suite("API tokens")
    struct TokenAccessTests {
        private static let secret = "test-token-secret-of-sufficient-length"

        private func withTokenServer(_ body: (Application) async throws -> Void) async throws {
            try await APITestSupport.withServer { app in
                app.apiTokens = APIToken.parse("shortcuts:\(Self.secret)")
                try await body(app)
            }
        }

        private static func bearer(_ secret: String = secret) -> HTTPHeaders {
            var headers = HTTPHeaders()
            headers.bearerAuthorization = BearerAuthorization(token: secret)
            return headers
        }

        @Test("A token reads the dashboard without a sign-in")
        func tokenReads() async throws {
            try await withTokenServer { app in
                _ = try await APITestSupport.createExpense(app, name: "Prąd", amount: 200)

                try await app.testing().test(.GET, "/api/expenses", headers: Self.bearer()) { response in
                    #expect(response.status == .ok)
                    #expect(response.body.string.contains("Prąd"))
                }
            }
        }

        @Test("X-API-Key works as well as a bearer token")
        func acceptsAPIKeyHeader() async throws {
            try await withTokenServer { app in
                var headers = HTTPHeaders()
                headers.add(name: "X-API-Key", value: Self.secret)
                try await app.testing().test(.GET, "/api/expenses", headers: headers) { response in
                    #expect(response.status == .ok)
                }
            }
        }

        @Test("A token cannot write")
        func tokenCannotWrite() async throws {
            try await withTokenServer { app in
                var headers = Self.bearer()
                headers.add(name: "Content-Type", value: "application/json")

                try await app.testing().test(
                    .POST, "/api/expenses", headers: headers,
                    beforeRequest: { request in
                        request.body = ByteBuffer(
                            string: """
                                {"name":"Nope","amount":1,"frequency":"monthly","due_day":1,
                                  "category":"Inne","active":true,"is_variable":false,"due_month":null}
                                """)
                    }
                ) { response in
                    #expect(response.status == .forbidden)
                }
            }
        }

        @Test("Marking a bill paid is a write, so a token cannot do it either")
        func tokenCannotPay() async throws {
            try await withTokenServer { app in
                let id = try await APITestSupport.createExpense(app, name: "Gaz")
                try await app.testing().test(
                    .POST, "/api/expenses/\(id)/pay", headers: Self.bearer()
                ) { response in
                    #expect(response.status == .forbidden)
                }
            }
        }

        @Test("A token cannot delete")
        func tokenCannotDelete() async throws {
            try await withTokenServer { app in
                let id = try await APITestSupport.createExpense(app, name: "Woda")
                try await app.testing().test(.DELETE, "/api/expenses/\(id)", headers: Self.bearer()) {
                    response in
                    #expect(response.status == .forbidden)
                }
            }
        }

        @Test("An unknown token is refused rather than falling back to the header path")
        func unknownTokenRefused() async throws {
            try await withTokenServer { app in
                // Both credentials present: the token is wrong, and the header would otherwise be
                // trusted. Presenting a token must not be a way to *lower* the bar.
                var headers = Self.bearer("wrong-secret-of-sufficient-length-xx")
                headers.add(name: "X-Forwarded-User", value: "konrad")

                try await app.testing().test(.GET, "/api/expenses", headers: headers) { response in
                    #expect(response.status == .unauthorized)
                }
            }
        }

        @Test("With no tokens configured, no token opens anything")
        func disabledByDefault() async throws {
            try await APITestSupport.withServer { app in
                try await app.testing().test(.GET, "/api/expenses", headers: Self.bearer()) { response in
                    #expect(response.status == .unauthorized)
                }
            }
        }

        @Test("The caller's own name is what the API reports back")
        func whoamiNamesTheClient() async throws {
            try await withTokenServer { app in
                try await app.testing().test(.GET, "/api/whoami", headers: Self.bearer()) { response in
                    #expect(response.status == .ok)
                    #expect(response.body.string.contains("shortcuts"))
                }
            }
        }

        @Test("A person signing in through Authelia still writes")
        func headerPathUnaffected() async throws {
            try await withTokenServer { app in
                // The whole point of the read-only rule is that it applies to tokens and to nothing
                // else. Turning tokens on must not make the browser read-only too.
                let id = try await APITestSupport.createExpense(app, name: "Internet")
                #expect(!id.isEmpty)
            }
        }
    }
}
