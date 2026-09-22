import Vapor

enum NtfyError: Error, CustomStringConvertible {
    case rejected(status: HTTPStatus, body: String)

    var description: String {
        switch self {
        case .rejected(let status, let body):
            return "ntfy odrzucił zgłoszenie (\(status.code)): \(body)"
        }
    }
}

/// Where to publish, and as whom.
///
/// Absent configuration is not an error: it turns the push off. Same rule as the API tokens —
/// a feature nobody configured is a feature that does nothing, rather than one that fails at boot.
struct NtfyConfiguration: Sendable {
    var url: String
    var topic: String
    var username: String?
    var password: String?
    /// How many days ahead to look. The daily push answers "what do I owe this week?".
    var windowDays: Int
    /// Local hour and minute to publish at.
    var hour: Int
    var minute: Int

    static func fromEnvironment() -> NtfyConfiguration? {
        make { Environment.get($0) }
    }

    /// Takes the lookup rather than reading the process environment directly, so the defaults can
    /// be tested without `setenv` - which leaks between tests running in parallel.
    static func make(_ value: (String) -> String?) -> NtfyConfiguration? {
        func nonEmpty(_ key: String) -> String? {
            value(key).flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let url = nonEmpty("NTFY_URL"), let topic = nonEmpty("NTFY_TOPIC") else { return nil }

        return NtfyConfiguration(
            url: url,
            topic: topic,
            username: nonEmpty("NTFY_USER"),
            password: nonEmpty("NTFY_PASSWORD"),
            windowDays: nonEmpty("NTFY_DUE_WINDOW_DAYS").flatMap(Int.init) ?? 5,
            hour: nonEmpty("NTFY_DIGEST_HOUR").flatMap(Int.init) ?? 8,
            minute: nonEmpty("NTFY_DIGEST_MINUTE").flatMap(Int.init) ?? 0
        )
    }
}

/// Publishes a notification to a self-hosted ntfy server.
///
/// JSON rather than the plain-text form, because the title and body travel as fields instead of
/// headers — a bill named with Polish diacritics is not something to put in an HTTP header.
struct NtfyClient {
    let configuration: NtfyConfiguration
    let client: any Client
    let logger: Logger

    struct Payload: Content {
        let topic: String
        let title: String
        let message: String
        let priority: Int
        let tags: [String]
    }

    func send(title: String, message: String, priority: Int = 4, tags: [String] = ["moneybag"])
        async throws
    {
        var headers = HTTPHeaders()
        if let username = configuration.username, let password = configuration.password {
            headers.basicAuthorization = BasicAuthorization(username: username, password: password)
        }

        let response = try await client.post(URI(string: configuration.url), headers: headers) {
            request in
            try request.content.encode(
                Payload(
                    topic: configuration.topic, title: title, message: message,
                    priority: priority, tags: tags))
        }

        guard response.status == .ok else {
            let body = response.body.map { String(buffer: $0) } ?? ""
            throw NtfyError.rejected(status: response.status, body: body)
        }
    }
}
