import HomeBudgetCore
import NIOConcurrencyHelpers
import NIOCore
import NIOPosix
import Testing
import Vapor

@testable import App

/// A `Client` that answers with a canned response and keeps what it was asked to send.
///
/// Enough of the protocol to stand in for the real one: everything else has a default. The
/// recorded requests live behind a lock because `Client` is `Sendable` and the request is written
/// on whichever thread the call happens to be on.
private final class RecordingClient: Client, @unchecked Sendable {
    let eventLoop: EventLoop
    private let status: HTTPStatus
    private let responseBody: String
    private let recorded = NIOLockedValueBox<[ClientRequest]>([])

    init(eventLoop: EventLoop, status: HTTPStatus = .ok, responseBody: String = "") {
        self.eventLoop = eventLoop
        self.status = status
        self.responseBody = responseBody
    }

    var requests: [ClientRequest] { recorded.withLockedValue { $0 } }

    func delegating(to eventLoop: EventLoop) -> any Client { self }

    func send(_ request: ClientRequest) -> EventLoopFuture<ClientResponse> {
        recorded.withLockedValue { $0.append(request) }
        var body: ByteBuffer?
        if !responseBody.isEmpty {
            body = ByteBufferAllocator().buffer(string: responseBody)
        }
        return eventLoop.makeSucceededFuture(
            ClientResponse(status: status, headers: [:], body: body))
    }
}

@Suite("ntfy client")
struct NtfyClientTests {
    private let group = MultiThreadedEventLoopGroup.singleton

    private func configuration(user: String? = "labalerts", password: String? = "secret")
        -> NtfyConfiguration
    {
        NtfyConfiguration(
            url: "http://ntfy.invalid:8095/", topic: "lab-alerts", username: user,
            password: password, windowDays: 5, hour: 8, minute: 0)
    }

    private struct SentPayload: Codable {
        let topic: String
        let title: String
        let message: String
        let priority: Int
        let tags: [String]
    }

    private func payload(of request: ClientRequest) throws -> SentPayload {
        var request = request
        return try request.content.decode(SentPayload.self)
    }

    @Test("Posts to the configured URL")
    func postsToConfiguredURL() async throws {
        let client = RecordingClient(eventLoop: group.next())

        try await NtfyClient(configuration: configuration(), client: client, logger: Logger(label: "test"))
            .send(title: "t", message: "m")

        #expect(client.requests.count == 1)
        #expect(client.requests[0].method == .POST)
        #expect(client.requests[0].url.string == "http://ntfy.invalid:8095/")
    }

    /// The topic travels in the body rather than the path, and the title in a field rather than a
    /// header — a bill named "Śmieci" is not something to put in an HTTP header.
    @Test("Carries topic, title, message, priority and tags in the body")
    func carriesEveryField() async throws {
        let client = RecordingClient(eventLoop: group.next())

        try await NtfyClient(configuration: configuration(), client: client, logger: Logger(label: "test"))
            .send(
                title: "HomeBudget: 2 alerty", message: "• Śmieci — 300,00 zł", priority: 5, tags: ["a", "b"])

        let sent = try payload(of: client.requests[0])
        #expect(sent.topic == "lab-alerts")
        #expect(sent.title == "HomeBudget: 2 alerty")
        #expect(sent.message == "• Śmieci — 300,00 zł")
        #expect(sent.priority == 5)
        #expect(sent.tags == ["a", "b"])
    }

    @Test("Sends basic auth when credentials are configured")
    func sendsBasicAuth() async throws {
        let client = RecordingClient(eventLoop: group.next())

        try await NtfyClient(configuration: configuration(), client: client, logger: Logger(label: "test"))
            .send(title: "t", message: "m")

        let auth = client.requests[0].headers.basicAuthorization
        #expect(auth?.username == "labalerts")
        #expect(auth?.password == "secret")
    }

    /// The lab's ntfy denies anonymous publishing, so a missing password must not silently become
    /// an empty one — that would fail as a bad credential rather than an absent one.
    @Test("Sends no auth header when credentials are absent")
    func omitsAuthWithoutCredentials() async throws {
        let client = RecordingClient(eventLoop: group.next())

        try await NtfyClient(
            configuration: configuration(user: nil, password: nil), client: client,
            logger: Logger(label: "test")
        ).send(title: "t", message: "m")

        #expect(client.requests[0].headers.basicAuthorization == nil)
    }

    @Test("A rejected publish throws rather than reporting success")
    func throwsOnRejection() async throws {
        let client = RecordingClient(eventLoop: group.next(), status: .forbidden, responseBody: "denied")

        await #expect(throws: NtfyError.self) {
            try await NtfyClient(
                configuration: configuration(), client: client, logger: Logger(label: "test")
            ).send(title: "t", message: "m")
        }
    }

    @Test("The error says what the server answered")
    func errorCarriesTheServerReply() async throws {
        let client = RecordingClient(eventLoop: group.next(), status: .forbidden, responseBody: "denied")

        do {
            try await NtfyClient(
                configuration: configuration(), client: client, logger: Logger(label: "test")
            ).send(title: "t", message: "m")
            Issue.record("expected the publish to throw")
        } catch let error as NtfyError {
            #expect("\(error)".contains("403"))
            #expect("\(error)".contains("denied"))
        }
    }

    @Test("Defaults to a moneybag at ordinary priority")
    func defaultPriorityAndTags() async throws {
        let client = RecordingClient(eventLoop: group.next())

        try await NtfyClient(configuration: configuration(), client: client, logger: Logger(label: "test"))
            .send(title: "t", message: "m")

        let sent = try payload(of: client.requests[0])
        #expect(sent.priority == 4)
        #expect(sent.tags == ["moneybag"])
    }
}

@Suite("Digest urgency")
struct DuePaymentDigestUrgencyTests {
    private let today = CalendarDate(year: 2026, month: 8, day: 15)

    private func dashboard(_ expenses: [Expense]) -> Dashboard {
        DashboardBuilder.build(expenses: expenses, today: today)
    }

    private func bill(id: String, dueDay: Int) -> Expense {
        Expense(
            id: id, name: id, amount: 100, frequency: .monthly, dueDay: dueDay,
            category: "Media i Eksploatacja")
    }

    @Test("Nothing overdue rings quietly")
    func quietWhenNothingOverdue() {
        // Due on the 17th: two days out, inside the window but not late.
        let due = dashboard([bill(id: "soon", dueDay: 17)]).duePayments(within: 5)

        #expect(DuePaymentDigest.urgency(for: due) == .init(priority: 3, tags: ["moneybag"]))
    }

    /// A missed payment should feel different from one due on Friday, or the digest becomes
    /// background noise and gets muted.
    @Test("An overdue bill raises the priority and adds a siren")
    func loudWhenOverdue() {
        // Due on the 10th: five days ago.
        let due = dashboard([bill(id: "late", dueDay: 10)]).duePayments(within: 5)

        let urgency = DuePaymentDigest.urgency(for: due)
        #expect(urgency.priority == 5)
        #expect(urgency.tags.contains("rotating_light"))
    }

    @Test("One overdue bill among several is enough to raise it")
    func oneOverdueIsEnough() {
        let due = dashboard([bill(id: "late", dueDay: 10), bill(id: "soon", dueDay: 17)])
            .duePayments(within: 5)

        #expect(due.count == 2)
        #expect(DuePaymentDigest.urgency(for: due).priority == 5)
    }
}
