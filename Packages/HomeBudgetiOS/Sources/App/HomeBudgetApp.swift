import HomeBudgetCore
import SwiftUI

@main
struct HomeBudgetApp: App {
    @State private var session = AutheliaSession(
        baseURL: ServerSettings.load().baseURL)

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
    }
}

/// Where the server lives. Kept in defaults rather than compiled in, so the same build works
/// against a laptop during development and the real host afterwards.
struct ServerSettings {
    var baseURL: URL

    private static let key = "serverURL"
    private static let fallback = URL(string: "https://rachunki.office.lab")!

    static func load() -> ServerSettings {
        let stored = UserDefaults.standard.string(forKey: key).flatMap(URL.init(string:))
        return ServerSettings(baseURL: stored ?? fallback)
    }

    static func save(_ url: URL) {
        UserDefaults.standard.set(url.absoluteString, forKey: key)
    }
}

struct RootView: View {
    let session: AutheliaSession
    @State private var showingLogin = false

    var body: some View {
        Group {
            switch session.state {
            case .unknown:
                ProgressView()
                    .task { await session.refresh() }

            case .signedIn:
                DashboardScreen(session: session)

            case .signedOut:
                SignInScreen(session: session) { showingLogin = true }

            case .failed(let message):
                SignInScreen(session: session, message: message) { showingLogin = true }
            }
        }
        .sheet(isPresented: $showingLogin) {
            NavigationStack {
                LoginWebView(
                    session: session,
                    onSignedIn: { showingLogin = false },
                    onFailure: { showingLogin = false })
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle("Logowanie")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Anuluj") { showingLogin = false }
                        }
                    }
            }
        }
    }
}

struct SignInScreen: View {
    let session: AutheliaSession
    var message: String?
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("HomeBudget")
                .font(.largeTitle.bold())

            Text("Zaloguj się przez Authelię, tak samo jak w przeglądarce.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button("Zaloguj się", action: onSignIn)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}
