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

    /// Every label follows the device's language, so the interface does not end up half in one and
    /// half in the other.
    private var language: Language { Language(code: Locale.current.language.languageCode?.identifier) }

    var body: some View {
        Group {
            switch session.state {
            case .unknown:
                ProgressView()
                    .task { await session.refresh() }

            case .signedIn:
                MainTabs(session: session)

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
                    .navigationTitle(UIString.signInTitle(language))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(UIString.actionCancel(language)) { showingLogin = false }
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

    private var language: Language { Language(code: Locale.current.language.languageCode?.identifier) }

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 56))
                .foregroundStyle(.tint)

            Text("HomeBudget")
                .font(.largeTitle.bold())

            Text(UIString.signInPrompt(language))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button(UIString.signIn(language), action: onSignIn)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .padding(32)
    }
}

/// The three views the app is built around, on a tab bar — which iOS 26 renders in the same glass
/// as everything else, and shrinks out of the way as content scrolls under it.
struct MainTabs: View {
    let session: AutheliaSession
    @State private var model: DashboardModel
    @State private var selection: Screen

    enum Screen: String, Hashable {
        case expenses, charts, calendar
    }

    init(session: AutheliaSession) {
        self.session = session
        _model = State(initialValue: DashboardModel(session: session))

        var start = Screen.expenses
        #if DEBUG
            if DevelopMode.isOn, let named = DevelopMode.initialTab,
                let screen = Screen(rawValue: named)
            {
                start = screen
            }
        #endif
        _selection = State(initialValue: start)
    }

    private var language: Language { .device }

    var body: some View {
        TabView(selection: $selection) {
            Tab(UIString.sectionExpenses(language), systemImage: "list.bullet", value: .expenses) {
                DashboardScreen(session: session, model: model)
            }
            Tab(UIString.viewCharts(language), systemImage: "chart.pie", value: .charts) {
                ChartsScreen(model: model)
            }
            Tab(UIString.viewCalendar(language), systemImage: "calendar", value: .calendar) {
                CalendarScreen(model: model)
            }
        }
        .task { if model.dashboard == nil { await model.load() } }
    }
}
