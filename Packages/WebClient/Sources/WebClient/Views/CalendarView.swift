import HomeBudgetCore
import JavaScriptKit

/// The month grid: which bills fall due on which day, and a way to settle one from there.
@MainActor
struct CalendarView {
    let state: AppState
    let onRender: () -> Void
    let onPay: (String) -> Void

    private var language: Language { state.language }

    static let weekdaysPL = ["Pon", "Wt", "Śr", "Czw", "Pt", "Sob", "Nie"]
    static let weekdaysEN = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    func render() -> JSObject {
        let grid = MonthGrid.build(
            year: state.calendarYear,
            month: state.calendarMonth,
            expenses: state.dashboard?.expenses.map(\.expense) ?? [],
            today: .today()
        )

        let panel = DOM.element("section", class: "card")
        panel.appending(header(grid))

        let table = DOM.element("div", class: "calendar")
        for weekday in (language == .pl ? Self.weekdaysPL : Self.weekdaysEN) {
            table.appending(DOM.element("div", class: "calendar-weekday", text: weekday))
        }
        for _ in 0..<grid.leadingBlanks {
            table.appending(DOM.element("div", class: "calendar-cell blank"))
        }
        for day in grid.days {
            table.appending(cell(day))
        }

        return panel.appending(table)
    }

    private func header(_ grid: MonthGrid) -> JSObject {
        let previous = DOM.element("button", class: "icon-button", text: "‹")
        previous.on("click") { step(-1) }

        let next = DOM.element("button", class: "icon-button", text: "›")
        next.on("click") { step(1) }

        let title = DOM.element(
            "h2", class: "grow",
            text: "\(Localization.monthName(grid.month, language: language)) \(grid.year)")

        let todayButton = DOM.element(
            "button", class: "chip", text: language == .pl ? "Dziś" : "Today")
        todayButton.on("click") {
            let today = CalendarDate.today()
            state.calendarYear = today.year
            state.calendarMonth = today.month
            onRender()
        }

        return DOM.element("div", class: "card-head").appending(title, previous, todayButton, next)
    }

    private func step(_ offset: Int) {
        let absolute = (state.calendarYear * 12 + state.calendarMonth - 1) + offset
        state.calendarYear = absolute / 12
        state.calendarMonth = absolute % 12 + 1
        onRender()
    }

    private func cell(_ day: MonthGrid.Day) -> JSObject {
        let cell = DOM.element("div", class: "calendar-cell \(day.isToday ? "today" : "")")
        cell.appending(DOM.element("span", class: "calendar-day", text: "\(day.date.day)"))

        for entry in day.entries {
            let chip = DOM.element("button", class: "calendar-chip \(entry.status.rawValue)")
            chip.attribute(
                "title",
                "\(entry.name) — \(NumberFormatting.currency(entry.amount, language: language))")
            chip.appending(DOM.element("span", class: "calendar-chip-name", text: entry.name))
            chip.on("click") { onPay(entry.id) }
            cell.appending(chip)
        }

        return cell
    }
}
