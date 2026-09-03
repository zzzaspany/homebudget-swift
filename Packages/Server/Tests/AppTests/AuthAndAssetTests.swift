import Testing
import VaporTesting

@testable import App

/// Covers everything reachable without a live database — identity headers and static assets.
/// Port of the dashboard and PWA assertions in the Python app's `test_reports_and_pwa.py`.
@Suite("Auth and static assets")
struct AuthAndAssetTests {
    private func withServer(devMode: Bool, _ body: (Application) async throws -> Void) async throws {
        let app = try await Application.make(.testing)
        do {
            try await configure(app)
            app.devMode = devMode
            try await body(app)
        } catch {
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    @Test("Requests without identity headers are rejected")
    func rejectsAnonymous() async throws {
        try await withServer(devMode: false) { app in
            try await app.testing().test(.GET, "/api/expenses") { response in
                #expect(response.status == .unauthorized)
            }
        }
    }

    @Test("A forwarded identity header is accepted")
    func acceptsForwardedUser() async throws {
        try await withServer(devMode: false) { app in
            try await app.testing().test(
                .GET, "/", headers: ["X-Forwarded-User": "testuser"]
            ) { response in
                // The dashboard renders; the database is never touched by this route.
                #expect(response.status == .ok)
                #expect(response.body.string.contains("testuser"))
            }
        }
    }

    @Test("Dev mode substitutes a local user")
    func devModeBypass() async throws {
        try await withServer(devMode: true) { app in
            try await app.testing().test(.GET, "/") { response in
                #expect(response.status == .ok)
            }
        }
    }

    @Test("PWA assets are served")
    func pwaAssets() async throws {
        try await withServer(devMode: true) { app in
            try await app.testing().test(.GET, "/manifest.json") { response in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("HomeBudget"))
            }
            try await app.testing().test(.GET, "/sw.js") { response in
                #expect(response.status == .ok)
                #expect(response.body.string.contains("CACHE_NAME"))
            }
        }
    }

    @Test("Health check needs no identity")
    func health() async throws {
        try await withServer(devMode: false) { app in
            try await app.testing().test(.GET, "/health") { response in
                #expect(response.status == .ok)
            }
        }
    }
}

@Suite("Invoice filename handling")
struct InvoiceStorageTests {
    @Test("Uploaded filenames cannot escape the storage directory")
    func sanitizesPaths() {
        #expect(InvoiceStorage.sanitize("../../etc/passwd") == "passwd")
        #expect(InvoiceStorage.sanitize("faktura 01.pdf") == "faktura_01.pdf")
        #expect(InvoiceStorage.sanitize("archiwum/2026.pdf") == "2026.pdf")
        #expect(InvoiceStorage.sanitize("..") == "invoice")
        #expect(InvoiceStorage.sanitize("rachunek.pdf") == "rachunek.pdf")
    }
}
