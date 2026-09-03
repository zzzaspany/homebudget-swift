import Vapor

/// The embedded report fonts, parsed once and kept for the life of the process.
///
/// Parsing walks the whole character map, which is wasted work to repeat on every download.
struct ReportFonts {
    let regular: TrueTypeFont
    let bold: TrueTypeFont
}

extension Application {
    private struct ReportFontsKey: StorageKey {
        typealias Value = ReportFonts
    }

    func reportFonts() throws -> ReportFonts {
        if let cached = storage[ReportFontsKey.self] { return cached }

        let directory = directory.resourcesDirectory + "Fonts/"
        let fonts = ReportFonts(
            regular: try TrueTypeFont(path: directory + "DejaVuSans.ttf"),
            bold: try TrueTypeFont(path: directory + "DejaVuSans-Bold.ttf")
        )
        storage[ReportFontsKey.self] = fonts
        return fonts
    }
}
