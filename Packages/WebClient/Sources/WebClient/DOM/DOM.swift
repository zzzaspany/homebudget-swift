import JavaScriptKit

/// A thin layer over the DOM.
///
/// Deliberately small: there is no virtual DOM here, panels re-render by replacing their own
/// subtree. The data set is a household's bills, so the cost of that is irrelevant and it keeps
/// the rendering code readable.
@MainActor
enum DOM {
    static let document = JSObject.global.document
    static let window = JSObject.global.window

    static func element(_ tag: String, class className: String? = nil, text: String? = nil) -> JSObject {
        let node = document.createElement(tag).object!
        if let className { node.className = .string(className) }
        if let text { node.textContent = .string(text) }
        return node
    }

    static func byID(_ id: String) -> JSObject? {
        document.getElementById(id).object
    }
}

extension JSObject {
    @MainActor
    @discardableResult
    func appending(_ children: JSObject...) -> JSObject {
        appending(children)
    }

    @MainActor
    @discardableResult
    func appending(_ children: [JSObject]) -> JSObject {
        for child in children { _ = self.appendChild!(child) }
        return self
    }

    @MainActor
    func removeAllChildren() {
        self.innerHTML = .string("")
    }

    /// Named to avoid shadowing the DOM's own `remove`, which this calls.
    @MainActor
    func removeFromParent() {
        _ = self.remove!()
    }

    /// Named `attribute` rather than `setAttribute` so it does not shadow the DOM method it calls.
    @MainActor
    func attribute(_ name: String, _ value: String) {
        _ = self.setAttribute!(name, value)
    }

    @MainActor
    func on(_ event: String, _ handler: @escaping () -> Void) {
        let closure = JSClosure { _ in
            handler()
            return .undefined
        }
        _ = self.addEventListener!(event, closure)
        // The listener lives as long as the page does, so the closure is intentionally retained.
        JSClosureRetainer.shared.retain(closure)
    }
}

/// Keeps event-handler closures alive for the lifetime of the page.
@MainActor
final class JSClosureRetainer {
    static let shared = JSClosureRetainer()
    private var closures: [JSClosure] = []

    func retain(_ closure: JSClosure) {
        closures.append(closure)
    }
}
