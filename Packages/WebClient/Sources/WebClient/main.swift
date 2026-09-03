import HomeBudgetCore
import JavaScriptEventLoop
import JavaScriptKit

// Bridges Swift's concurrency to the browser's event loop, so `await` on a JS promise works.
JavaScriptEventLoop.installGlobalExecutor()

let state = AppState()
let root = DOM.byID("app") ?? DOM.document.body.object!

applyTheme(state.theme)

/// Rebuilds the UI from the state already in memory.
///
/// Every panel replaces its own subtree rather than being diffed: at the scale of a household's
/// bill list that costs nothing, and it keeps the rendering code free of a reconciliation layer.
/// The one thing a full rebuild does lose is focus, so the search field is restored afterwards.
@MainActor
func render() {
    let searchWasFocused = DOM.document.activeElement.object?.id.string == DashboardView.searchFieldID

    DashboardView(state: state, onRender: render, onRefresh: refresh).render(into: root)

    if searchWasFocused, let search = DOM.byID(DashboardView.searchFieldID) {
        _ = search.focus!()
        let end = state.search.count
        _ = search.setSelectionRange!(end, end)
    }
}

/// Pulls fresh data from the API, then rebuilds.
@MainActor
func refresh() {
    Task {
        await state.reload()
        render()
    }
}

render()
refresh()
