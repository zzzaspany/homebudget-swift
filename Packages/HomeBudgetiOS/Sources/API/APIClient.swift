import Foundation
import HomeBudgetCore

enum APIError: LocalizedError {
    case signedOut
    case status(Int, String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Sesja wygasła"
        case .status(let code, let reason): return reason.isEmpty ? "Błąd \(code)" : reason
        case .transport(let message): return message
        }
    }
}

/// Talks to the same API the browser uses, over the session the web view signed in with.
struct APIClient {
    let session: AutheliaSession

    private var decoder: JSONDecoder { JSONDecoder() }

    func dashboard() async throws -> Dashboard {
        try await get("api/expenses")
    }

    func payments() async throws -> [PaymentRecord] {
        try await get("api/payments")
    }

    func history(expenseID: String) async throws -> PriceHistory {
        try await get("api/expenses/\(expenseID)/history")
    }

    @discardableResult
    func pay(expenseID: String, amount: Double?) async throws -> Expense {
        var body: [String: Any] = [:]
        body["amount_paid"] = amount ?? NSNull()
        return try await send("api/expenses/\(expenseID)/pay", method: "POST", body: body)
    }

    @discardableResult
    func createExpense(_ input: ExpenseInput) async throws -> Expense {
        try await send("api/expenses", method: "POST", body: input.json)
    }

    @discardableResult
    func updateExpense(id: String, _ input: ExpenseInput) async throws -> Expense {
        try await send("api/expenses/\(id)", method: "PUT", body: input.json)
    }

    func deleteExpense(id: String) async throws {
        _ = try await raw("api/expenses/\(id)", method: "DELETE", body: nil)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await raw(path, method: "GET", body: nil))
    }

    private func send<T: Decodable>(
        _ path: String, method: String, body: [String: Any]
    ) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try decode(try await raw(path, method: method, body: data))
    }

    private func raw(_ path: String, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: session.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.authenticatedSession.data(for: request)
        } catch {
            throw APIError.transport((error as NSError).localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Brak odpowiedzi serwera")
        }

        // An expired session is a redirect to the identity provider, not a 401, so a response
        // that came from somewhere other than our own host means we have been signed out.
        if http.url?.host != session.baseURL.host || http.statusCode == 401 {
            throw APIError.signedOut
        }

        guard (200..<300).contains(http.statusCode) else {
            struct Failure: Decodable { let reason: String }
            let reason = (try? decoder.decode(Failure.self, from: data))?.reason ?? ""
            throw APIError.status(http.statusCode, reason)
        }

        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.transport("Nie udało się odczytać odpowiedzi: \(error)")
        }
    }
}

struct ExpenseInput {
    var name: String
    var amount: Double
    var frequency: Frequency
    var dueDay: Int
    var dueMonth: Int?
    var category: String
    var active: Bool
    var isVariable: Bool

    var json: [String: Any] {
        [
            "name": name,
            "amount": amount,
            "frequency": frequency.rawValue,
            "due_day": dueDay,
            "due_month": dueMonth as Any? ?? NSNull(),
            "category": category,
            "active": active,
            "is_variable": isVariable,
        ]
    }
}
