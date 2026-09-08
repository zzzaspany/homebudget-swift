import Foundation
import HomeBudgetCore

extension Language {
    /// The device's language, falling back to Polish for anything the app does not translate.
    ///
    /// In `Shared` rather than beside a view, because the widget extension is a separate target and
    /// needs it too.
    static var device: Language {
        Language(code: Locale.current.language.languageCode?.identifier)
    }
}
