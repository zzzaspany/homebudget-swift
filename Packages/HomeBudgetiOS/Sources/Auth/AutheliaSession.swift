import Foundation
import HomeBudgetCore
import Observation
import WebKit

/// Holds the Authelia session the app authenticates with.
///
/// The server has one way of knowing who you are: identity headers set by the reverse proxy for a
/// request carrying a valid Authelia cookie. Rather than adding a second path for native clients —
/// a token endpoint, its own expiry, its own bugs — the app signs in the same way the browser does
/// and carries the same cookie.
///
/// The cookie is handed to `URLSession` after a web view obtains it. The two do not share storage,
/// so it has to be copied across deliberately.
@MainActor
@Observable
final class AutheliaSession {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(user: String)
        case failed(String)
    }

    private(set) var state: State = .unknown

    /// Where the app lives. Authelia protects it and redirects to its own domain to sign in.
    let baseURL: URL
    private let cookieName: String
    private let storage: HTTPCookieStorage
    private let session: URLSession

    init(baseURL: URL, cookieName: String = "authelia_session") {
        self.baseURL = baseURL
        self.cookieName = cookieName

        // A named container, so the cookie survives relaunches without being written anywhere the
        // app has to manage itself.
        let configuration = URLSessionConfiguration.default
        storage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "lab.office.homebudget")
        configuration.httpCookieStorage = storage
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
    }

    var authenticatedSession: URLSession { session }

    var hasCookie: Bool {
        storage.cookies(for: baseURL)?.contains { $0.name == cookieName } ?? false
    }

    /// Asks the server who it thinks we are.
    ///
    /// Authelia answers an unauthenticated request with a redirect to its login page rather than a
    /// 401, so a redirect away from our own host means the session is gone.
    func refresh() async {
        #if DEBUG
            if DevelopMode.isOn {
                state = .signedIn(user: UIString.developMode(.pl))
                return
            }
        #endif

        guard hasCookie else {
            state = .signedOut
            return
        }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/whoami"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                state = .failed("Brak odpowiedzi serwera")
                return
            }

            // A redirect to the identity provider, or a 401, both mean the session expired.
            if http.url?.host != baseURL.host || http.statusCode == 401 {
                state = .signedOut
                return
            }

            struct Identity: Decodable { let name: String }
            let identity = try JSONDecoder().decode(Identity.self, from: data)
            state = .signedIn(user: identity.name)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Copies the cookies a web view obtained into the store `URLSession` reads from.
    func adopt(cookies: [HTTPCookie]) {
        for cookie in cookies where cookie.name == cookieName {
            storage.setCookie(cookie)
        }
    }

    /// Surfaces a navigation failure in terms the person holding the phone can act on.
    func report(_ error: any Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
            nsError.code == NSURLErrorServerCertificateUntrusted
                || nsError.code == NSURLErrorServerCertificateHasUnknownRoot
        {
            state = .failed(
                "Certyfikat serwera nie jest zaufany. Zainstaluj na urządzeniu certyfikat "
                    + "głównego urzędu certyfikacji sieci lokalnej.")
        } else {
            state = .failed(nsError.localizedDescription)
        }
    }

    /// Drops the session locally. Authelia keeps its own record until it expires.
    func signOut() async {
        for cookie in storage.cookies ?? [] {
            storage.deleteCookie(cookie)
        }
        let store = WKWebsiteDataStore.default()
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        await store.removeData(ofTypes: types, modifiedSince: .distantPast)
        state = .signedOut
    }
}
