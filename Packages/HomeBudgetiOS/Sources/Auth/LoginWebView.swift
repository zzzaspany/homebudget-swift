import SwiftUI
import WebKit

/// Presents Authelia's own login page and takes the resulting session cookie.
///
/// A web view rather than `ASWebAuthenticationSession`: that API is built around a redirect back to
/// a custom scheme carrying a token, which is the second authentication mechanism we are avoiding.
/// What we want is the cookie itself, and only a web view will hand it over.
struct LoginWebView: UIViewRepresentable {
    let session: AutheliaSession
    let onSignedIn: () -> Void
    /// Called when the page cannot load at all. Without it the sheet sits there blank: the failure
    /// is recorded on the session, but the message is on the screen behind this one.
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onSignedIn: onSignedIn, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: session.baseURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        private let session: AutheliaSession
        private let onSignedIn: () -> Void
        private let onFailure: () -> Void

        init(
            session: AutheliaSession, onSignedIn: @escaping () -> Void,
            onFailure: @escaping () -> Void
        ) {
            self.session = session
            self.onSignedIn = onSignedIn
            self.onFailure = onFailure
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Landing back on the app's own host means Authelia let us through.
            guard webView.url?.host == session.baseURL.host else { return }

            Task {
                let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
                session.adopt(cookies: cookies)
                if session.hasCookie {
                    await session.refresh()
                    onSignedIn()
                }
            }
        }

        func webView(
            _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: any Error
        ) {
            // A certificate the device does not trust surfaces here, which is the likeliest
            // failure on a network using its own certificate authority.
            session.report(error)
            onFailure()
        }
    }
}
