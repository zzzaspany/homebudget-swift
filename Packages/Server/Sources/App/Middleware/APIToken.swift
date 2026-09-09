import Vapor

/// A named credential that lets a machine read the API without a browser session.
///
/// Everything on `office.lab` sits behind Authelia, which is a sign-in page — fine for a person,
/// useless for a shortcut, an automation or a script. A token is the way in for those, and it is
/// deliberately the *weaker* way in: a request carrying one may only read.
struct APIToken: Sendable {
    /// Who the token belongs to. Appears as the username on the request, so the access log and
    /// `/api/whoami` both say which client called.
    let name: String
    let secret: String

    /// The shortest secret worth accepting. A token is a password that never gets typed, so there
    /// is no reason for it to be short, and plenty of reason to refuse one that is.
    static let minimumSecretLength = 24

    /// Parses `name:secret` pairs separated by commas.
    ///
    /// Malformed and short entries are dropped rather than rejected wholesale — one bad pair in the
    /// environment should not take working clients offline. `report` receives a line for each, so
    /// the reason lands in the log at boot rather than in a 401 nobody can explain later.
    static func parse(_ raw: String, report: (String) -> Void = { _ in }) -> [APIToken] {
        raw.split(separator: ",").compactMap { entry in
            let text = entry.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }

            guard let separator = text.firstIndex(of: ":") else {
                report("API token entry has no name: expected 'name:secret'")
                return nil
            }

            let name = String(text[text.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            let secret = String(text[text.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty else {
                report("API token entry has an empty name")
                return nil
            }
            guard secret.count >= minimumSecretLength else {
                report("API token '\(name)' is shorter than \(minimumSecretLength) characters")
                return nil
            }

            return APIToken(name: name, secret: secret)
        }
    }

    /// The token a request presents, from either header a client is likely to reach for.
    static func presented(in request: Request) -> String? {
        if let bearer = request.headers.bearerAuthorization?.token, !bearer.isEmpty {
            return bearer
        }
        let key = request.headers.first(name: "X-API-Key")
        return (key?.isEmpty == false) ? key : nil
    }

    /// Finds the token matching a presented secret.
    ///
    /// The comparison runs over every candidate to the end, so the time it takes says nothing about
    /// how much of a secret was guessed correctly. Length is compared first because it cannot be
    /// hidden anyway — the header is on the wire.
    static func match(secret presented: String, in tokens: [APIToken]) -> APIToken? {
        let offered = Array(presented.utf8)
        var found: APIToken?

        for token in tokens {
            let expected = Array(token.secret.utf8)
            guard expected.count == offered.count else { continue }

            var difference: UInt8 = 0
            for index in expected.indices {
                difference |= expected[index] ^ offered[index]
            }
            if difference == 0, found == nil {
                found = token
            }
        }
        return found
    }
}

extension Application {
    private struct APITokensKey: StorageKey {
        typealias Value = [APIToken]
    }

    /// Read-only credentials for machine callers. Empty turns the feature off entirely — there is
    /// no built-in token, and an app nobody configured is an app nothing can call.
    var apiTokens: [APIToken] {
        get { storage[APITokensKey.self] ?? [] }
        set { storage[APITokensKey.self] = newValue }
    }
}
