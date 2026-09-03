import JavaScriptKit

/// Transient success/failure messages in the corner of the screen.
@MainActor
enum Toast {
    enum Kind: String {
        case success
        case failure
    }

    static func show(_ message: String, kind: Kind = .success) {
        let node = DOM.element("div", class: "toast \(kind.rawValue)", text: message)
        _ = DOM.document.body.object!.appendChild!(node)

        let dismiss = JSClosure { _ in
            _ = node.classList.object!.add!("leaving")
            let remove = JSClosure { _ in
                node.removeFromParent()
                return .undefined
            }
            _ = JSObject.global.setTimeout!(remove, 250)
            JSClosureRetainer.shared.retain(remove)
            return .undefined
        }
        _ = JSObject.global.setTimeout!(dismiss, 3500)
        JSClosureRetainer.shared.retain(dismiss)
    }
}

/// A centred dialog with a backdrop. Only one is open at a time.
@MainActor
enum Modal {
    private static let hostID = "modal-host"

    static func present(title: String, body: JSObject, actions: [JSObject]) {
        dismiss()

        let closeButton = DOM.element("button", class: "icon-button", text: "✕")
        closeButton.on("click") { dismiss() }

        let dialog = DOM.element("div", class: "modal").appending(
            DOM.element("div", class: "modal-head").appending(
                DOM.element("h2", text: title), closeButton),
            DOM.element("div", class: "modal-body").appending(body),
            DOM.element("div", class: "modal-actions").appending(actions)
        )

        let host = DOM.element("div", class: "modal-host")
        host.id = .string(hostID)
        host.appending(dialog)

        // Clicking the backdrop closes; clicks inside the dialog must not bubble up to it.
        let backdropClose = JSClosure { arguments in
            if arguments.first?.target.object == host { dismiss() }
            return .undefined
        }
        _ = host.addEventListener!("click", backdropClose)
        JSClosureRetainer.shared.retain(backdropClose)

        _ = DOM.document.body.object!.appendChild!(host)
    }

    static func dismiss() {
        DOM.byID(hostID)?.removeFromParent()
    }
}

@MainActor
func applyTheme(_ theme: Theme) {
    DOM.document.body.object!.className = .string(theme == .light ? "light-theme" : "")
}
