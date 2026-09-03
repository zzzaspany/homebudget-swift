import HomeBudgetCore
import JavaScriptKit

// Phase 0 feasibility spike. Proves the three things the web client depends on:
// HomeBudgetCore compiles to WebAssembly, the DOM is reachable, and localStorage round-trips —
// the last one matters because category budget thresholds are stored per browser.

let document = JSObject.global.document
let root = document.getElementById("app")

func text(_ value: String) -> JSValue {
    let node = document.createTextNode!(value)
    return node
}

func element(_ tag: String, _ className: String? = nil) -> JSValue {
    var node = document.createElement!(tag)
    if let className { node.className = .string(className) }
    return node
}

// 1. Domain logic running inside the browser.
let today = CalendarDate(year: 2026, month: 8, day: 15)
let expenses = [
    Expense(
        id: "1", name: "Czynsz", amount: 1000, frequency: .monthly, dueDay: 10,
        category: "Media i Eksploatacja"),
    Expense(
        id: "2", name: "Ubezpieczenie OC", amount: 1200, frequency: .yearly, dueDay: 15,
        dueMonth: 5, category: "Podatki"),
    Expense(
        id: "3", name: "Internet", amount: 120, frequency: .biweekly, dueDay: 17,
        category: "Media i Eksploatacja"),
]
let dashboard = DashboardBuilder.build(expenses: expenses, today: today)

// 2. localStorage round-trip.
let storage = JSObject.global.localStorage
_ = storage.setItem!("homebudget.spike", "ok")
let storedValue = storage.getItem!("homebudget.spike").string ?? "missing"

// 3. Render through the DOM.
var heading = element("h1")
_ = heading.appendChild!(text("HomeBudget — spike"))
_ = root.appendChild!(heading)

var list = element("ul")
let lines = [
    "Budżet miesięczny: \(NumberFormatting.currency(dashboard.kpis.proRatedMonthly, language: .pl))",
    "Rezerwa (sinking fund): \(NumberFormatting.currency(dashboard.kpis.sinkingFundTotal, language: .pl))",
    "Pozycje rezerwy: \(dashboard.sinkingFundItems.count)",
    "Prognoza na \(Localization.projectionLabel(year: dashboard.projection[0].year, month: dashboard.projection[0].month, language: .pl)): "
        + NumberFormatting.currency(dashboard.projection[0].amount, language: .pl),
    "localStorage: \(storedValue)",
]
for line in lines {
    var item = element("li")
    _ = item.appendChild!(text(line))
    _ = list.appendChild!(item)
}
_ = root.appendChild!(list)
