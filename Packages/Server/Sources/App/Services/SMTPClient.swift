import NIOCore
import NIOPosix
import Vapor

struct EmailMessage {
    let from: String
    let to: [String]
    let subject: String
    let htmlBody: String
}

enum SMTPError: Error, CustomStringConvertible {
    case notConfigured(String)
    case rejected(command: String, reply: String)
    case disconnected

    var description: String {
        switch self {
        case .notConfigured(let what): return "SMTP nie jest skonfigurowany: \(what)"
        case .rejected(let command, let reply): return "Serwer odrzucił \(command): \(reply)"
        case .disconnected: return "Serwer zamknął połączenie"
        }
    }
}

struct SMTPConfiguration {
    var host: String
    var port: Int
    var username: String?
    var password: String?
    var sender: String
    var recipient: String

    /// Reads the same variables the Python app used, so an existing environment file still works.
    static func fromEnvironment() throws -> SMTPConfiguration {
        guard let host = Environment.get("SMTP_HOST"), !host.isEmpty else {
            throw SMTPError.notConfigured("SMTP_HOST")
        }
        guard let recipient = Environment.get("NOTIFICATION_EMAIL_TO"), !recipient.isEmpty else {
            throw SMTPError.notConfigured("NOTIFICATION_EMAIL_TO")
        }

        return SMTPConfiguration(
            host: host,
            port: Environment.get("SMTP_PORT").flatMap(Int.init) ?? 25,
            username: Environment.get("SMTP_USER").flatMap { $0.isEmpty ? nil : $0 },
            password: Environment.get("SMTP_PASSWORD").flatMap { $0.isEmpty ? nil : $0 },
            sender: Environment.get("SMTP_FROM") ?? "homebudget@localhost",
            recipient: recipient
        )
    }
}

/// A minimal SMTP client, enough to hand a message to a relay.
///
/// Scope is deliberate: the relay this talks to accepts mail from the local network without
/// authentication and does TLS and credentials on the onward hop itself. AUTH LOGIN is here for
/// relays that want it; STARTTLS is not, so a server that demands encryption on the first hop is
/// not supported yet — it would need the connection upgraded mid-session.
struct SMTPClient {
    let configuration: SMTPConfiguration
    let logger: Logger

    func send(_ message: EmailMessage, on eventLoopGroup: any EventLoopGroup) async throws {
        let channel = try await ClientBootstrap(group: eventLoopGroup)
            .connectTimeout(.seconds(15))
            .connect(host: configuration.host, port: configuration.port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    try NIOAsyncChannel<ByteBuffer, ByteBuffer>(wrappingChannelSynchronously: channel)
                }
            }

        try await channel.executeThenClose { inbound, outbound in
            var lines = inbound.makeAsyncIterator()
            var pending = LineBuffer()

            func expect(_ codes: Set<Int>, after command: String) async throws {
                let reply = try await pending.nextReply(from: &lines)
                guard let code = reply.code, codes.contains(code) else {
                    throw SMTPError.rejected(command: command, reply: reply.text)
                }
            }

            func send(_ command: String, expecting codes: Set<Int>) async throws {
                try await outbound.write(ByteBuffer(string: command + "\r\n"))
                try await expect(codes, after: command.split(separator: " ").first.map(String.init) ?? command)
            }

            try await expect([220], after: "connect")
            try await send("EHLO homebudget", expecting: [250])

            if let username = configuration.username, let password = configuration.password {
                try await send("AUTH LOGIN", expecting: [334])
                try await send(Data(username.utf8).base64EncodedString(), expecting: [334])
                try await send(Data(password.utf8).base64EncodedString(), expecting: [235])
            }

            try await send("MAIL FROM:<\(configuration.sender)>", expecting: [250])
            for recipient in message.to {
                try await send("RCPT TO:<\(recipient)>", expecting: [250, 251])
            }
            try await send("DATA", expecting: [354])

            try await outbound.write(ByteBuffer(string: body(for: message)))
            try await expect([250], after: "message body")

            try await send("QUIT", expecting: [221])
        }

        logger.info("Sent payment reminder to \(message.to.joined(separator: ", "))")
    }

    /// The message itself, ending with the lone dot that closes DATA.
    private func body(for message: EmailMessage) -> String {
        let headers = [
            "From: \(message.from)",
            "To: \(message.to.joined(separator: ", "))",
            "Subject: \(encodeHeader(message.subject))",
            "MIME-Version: 1.0",
            "Content-Type: text/html; charset=utf-8",
            "Content-Transfer-Encoding: 8bit",
        ]

        // A line consisting of a single dot would end the message early, so it gets doubled.
        let escaped = message.htmlBody
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(".") ? "." + $0 : String($0) }
            .joined(separator: "\r\n")

        return headers.joined(separator: "\r\n") + "\r\n\r\n" + escaped + "\r\n.\r\n"
    }

    /// Subjects carry Polish characters, which headers may not hold as raw bytes.
    private func encodeHeader(_ value: String) -> String {
        guard value.unicodeScalars.contains(where: { !$0.isASCII }) else { return value }
        return "=?UTF-8?B?\(Data(value.utf8).base64EncodedString())?="
    }
}

/// Reassembles replies, which arrive in arbitrary chunks and may span several lines.
///
/// A multi-line reply repeats its code with a hyphen (`250-SIZE`) until the last line, which uses
/// a space (`250 OK`).
private struct LineBuffer {
    private var buffer = ""

    struct Reply {
        let code: Int?
        let text: String
    }

    mutating func nextReply(
        from lines: inout NIOAsyncChannelInboundStream<ByteBuffer>.AsyncIterator
    ) async throws -> Reply {
        while true {
            if let reply = takeCompleteReply() { return reply }
            guard let chunk = try await lines.next() else { throw SMTPError.disconnected }
            buffer += String(buffer: chunk)
        }
    }

    private mutating func takeCompleteReply() -> Reply? {
        var consumed: [String] = []
        var remainder = buffer

        while let range = remainder.range(of: "\r\n") {
            let line = String(remainder[remainder.startIndex..<range.lowerBound])
            remainder = String(remainder[range.upperBound...])
            consumed.append(line)

            // A space in the fourth position marks the final line of the reply.
            let characters = Array(line)
            if characters.count >= 4, characters[3] == " " {
                buffer = remainder
                return Reply(code: Int(String(characters[0..<3])), text: consumed.joined(separator: " "))
            }
        }
        return nil
    }
}
