import HomeBudgetCore
import JavaScriptKit

/// Per-browser settings: language, theme and the category budget ceilings.
///
/// These stay in `localStorage` rather than the database, matching the Python app — the ceilings
/// are a personal guide rather than shared household data.
@MainActor
enum Preferences {
    private static var storage: JSObject { JSObject.global.localStorage.object! }

    private static func read(_ key: String) -> String? {
        storage.getItem!(key).string
    }

    private static func write(_ key: String, _ value: String) {
        _ = storage.setItem!(key, value)
    }

    static var language: Language {
        get { Language(code: read("language")) }
        set { write("language", newValue.rawValue) }
    }

    static var theme: Theme {
        get { Theme(rawValue: read("theme") ?? "") ?? .dark }
        set { write("theme", newValue.rawValue) }
    }

    /// Default ceilings, overridden per category once the user edits one.
    static let defaultBudgets: [String: Double] = [
        "Media i Eksploatacja": 1000,
        "Kredyt i Ubezpieczenia": 2000,
        "Stałe Opłaty": 800,
        "Serwisy i Przeglądy": 500,
        "Podatki": 300,
        "Podatki i Ubezpieczenia": 800,
        "Bufor i Rezerwy": 500,
        "Inne": 300,
    ]

    static var categoryBudgets: [String: Double] {
        get {
            guard let raw = read("categoryBudgets"),
                let parsed = JSObject.global.JSON.parse(raw).object
            else { return [:] }

            var result: [String: Double] = [:]
            let keys = JSObject.global.Object.function!.keys!(parsed)
            let count = Int(keys.length.number ?? 0)
            for index in 0..<count {
                guard let key = keys[index].string, let value = parsed[key].number else { continue }
                result[key] = value
            }
            return result
        }
        set {
            let object = JSObject.global.Object.function!.new()
            for (key, value) in newValue { object[key] = .number(value) }
            write("categoryBudgets", JSObject.global.JSON.stringify(object).string ?? "{}")
        }
    }

    static func budget(for category: String) -> Double? {
        categoryBudgets[category] ?? defaultBudgets[category]
    }

    static func setBudget(_ amount: Double, for category: String) {
        var budgets = categoryBudgets
        budgets[category] = amount
        categoryBudgets = budgets
    }
}

enum Theme: String {
    case dark
    case light

    var next: Theme { self == .dark ? .light : .dark }
}
