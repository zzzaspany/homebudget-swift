import HomeBudgetCore
import JavaScriptEventLoop
import JavaScriptKit

enum APIError: Error, CustomStringConvertible {
    case request(String)
    case status(Int, String)
    case decoding(String)

    var description: String {
        switch self {
        case .request(let message): return message
        case .status(let code, let reason): return "HTTP \(code): \(reason)"
        case .decoding(let message): return "Nie udało się odczytać odpowiedzi: \(message)"
        }
    }
}

/// Talks to the Vapor API through the browser's `fetch`.
///
/// Deliberately not actor-isolated: `JSValue` is not `Sendable`, so the transport keeps those
/// values within one isolation domain and hands back only decoded, `Sendable` results.
///
/// Nothing here imports Foundation. Its `JSONDecoder` drags swift-foundation into the WebAssembly
/// binary — 9 MB became 60 MB — and the browser already has a JSON parser. `JSValueDecoder` maps
/// its output straight onto `Codable` types instead.
struct APIClient: Sendable {

    func dashboard() async throws -> Dashboard {
        try await get("/api/expenses")
    }

    func payments() async throws -> [PaymentRecord] {
        try await get("/api/payments")
    }

    func history(expenseID: String) async throws -> PriceHistory {
        try await get("/api/expenses/\(expenseID)/history")
    }

    @discardableResult
    func createExpense(_ body: ExpenseInput) async throws -> Expense {
        try await send("/api/expenses", method: "POST", body: body.jsonObject)
    }

    @discardableResult
    func updateExpense(id: String, _ body: ExpenseInput) async throws -> Expense {
        try await send("/api/expenses/\(id)", method: "PUT", body: body.jsonObject)
    }

    struct AlertEmailResult: Decodable, Sendable {
        let success: Bool
        let message: String
        let alertCount: Int
    }

    func sendAlertEmail(language: Language) async throws -> AlertEmailResult {
        let body = JSObject.global.Object.function!.new()
        return try await send(
            "/api/notifications/send-email?lang=\(language.rawValue)", method: "POST", body: body)
    }

    func deleteExpense(id: String) async throws {
        _ = try await raw("/api/expenses/\(id)", method: "DELETE", body: nil)
    }

    @discardableResult
    func pay(expenseID: String, amount: Double?, invoice: JSValue? = nil) async throws -> Expense {
        // With an attachment the request has to be multipart, which the browser assembles from a
        // FormData body — including the boundary header, which is why none is set here.
        if let invoice, !invoice.isNull, !invoice.isUndefined {
            let form = JSObject.global.FormData.function!.new()
            if let amount { _ = form.append!("amount_paid", NumberFormatting.plain(amount)) }
            _ = form.append!("invoice_file", invoice)
            return try decode(try await raw("/api/expenses/\(expenseID)/pay", method: "POST", form: form))
        }

        let body = JSObject.global.Object.function!.new()
        body["amount_paid"] = amount.map { JSValue.number($0) } ?? .null
        return try await send("/api/expenses/\(expenseID)/pay", method: "POST", body: body)
    }

    // MARK: - Transport

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try decode(try await raw(path, method: "GET", body: nil))
    }

    private func send<T: Decodable>(_ path: String, method: String, body: JSObject) async throws -> T {
        let json = JSObject.global.JSON.stringify(body).string ?? "{}"
        return try decode(try await raw(path, method: method, body: json))
    }

    private func raw(_ path: String, method: String, form: JSObject) async throws -> String {
        let options = JSObject.global.Object.function!.new()
        options["method"] = .string(method)
        options["body"] = .object(form)
        return try await perform(path, options: options)
    }

    private func raw(_ path: String, method: String, body: String?) async throws -> String {
        let options = JSObject.global.Object.function!.new()
        options["method"] = .string(method)

        if let body {
            options["body"] = .string(body)
            let headers = JSObject.global.Object.function!.new()
            headers["Content-Type"] = .string("application/json")
            options["headers"] = .object(headers)
        }

        return try await perform(path, options: options)
    }

    private func perform(_ path: String, options: JSObject) async throws -> String {

        guard let promiseObject = JSObject.global.fetch!(path, options).object,
            let promise = JSPromise(promiseObject)
        else {
            throw APIError.request("fetch nie zwrócił obietnicy")
        }

        let response: JSValue
        do {
            response = try await promise.value
        } catch {
            throw APIError.request("Brak połączenia z serwerem")
        }

        let status = Int(response.status.number ?? 0)
        guard let textObject = response.text().object, let textPromise = JSPromise(textObject) else {
            throw APIError.request("Nie udało się odczytać treści odpowiedzi")
        }
        let text = (try? await textPromise.value)?.string ?? ""

        guard (200..<300).contains(status) else {
            throw APIError.status(status, reason(from: text))
        }
        return text
    }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        guard !json.isEmpty else { throw APIError.decoding("pusta odpowiedź") }
        let parsed = JSObject.global.JSON.parse(json)
        do {
            return try JSValueDecoder().decode(T.self, from: parsed)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Vapor reports failures as `{"error": true, "reason": "..."}`.
    private func reason(from body: String) -> String {
        guard !body.isEmpty else { return "" }
        return JSObject.global.JSON.parse(body).reason.string ?? body
    }
}

/// Request body for creating or updating an expense.
///
/// Built as a `JSObject` rather than encoded with `Codable`, since there is no Foundation-free
/// encoder in JavaScriptKit and the shape is small enough to write out.
struct ExpenseInput {
    var name: String
    var amount: Double
    var frequency: Frequency
    var dueDay: Int
    var dueMonth: Int?
    var category: String
    var active: Bool
    var isVariable: Bool

    var jsonObject: JSObject {
        let object = JSObject.global.Object.function!.new()
        object["name"] = .string(name)
        object["amount"] = .number(amount)
        object["frequency"] = .string(frequency.rawValue)
        object["due_day"] = .number(Double(dueDay))
        object["due_month"] = dueMonth.map { JSValue.number(Double($0)) } ?? .null
        object["category"] = .string(category)
        object["active"] = .boolean(active)
        object["is_variable"] = .boolean(isVariable)
        return object
    }
}
