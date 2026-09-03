import Foundation
import HomeBudgetCore
import Testing

@testable import App

@Suite("PDF report")
struct PDFReportTests {
    let today = CalendarDate(year: 2026, month: 9, day: 3)

    func fonts() throws -> (regular: TrueTypeFont, bold: TrueTypeFont) {
        // Tests run from the package directory, where the resources live.
        let directory = FileManager.default.currentDirectoryPath + "/Resources/Fonts/"
        return (
            try TrueTypeFont(path: directory + "DejaVuSans.ttf"),
            try TrueTypeFont(path: directory + "DejaVuSans-Bold.ttf")
        )
    }

    func dashboard(expenseCount: Int) -> Dashboard {
        let expenses = (0..<expenseCount).map { index in
            Expense(
                id: "\(index)", name: "Opłata \(index) — prąd i gaz", amount: Double(index) * 12 + 50,
                frequency: index % 3 == 0 ? .yearly : .monthly, dueDay: index % 28 + 1,
                dueMonth: index % 12 + 1, category: "Media i Eksploatacja")
        }
        return DashboardBuilder.build(expenses: expenses, today: today)
    }

    func build(expenseCount: Int, language: Language = .pl) throws -> Data {
        let (regular, bold) = try fonts()
        return PDFReportBuilder(regular: regular, bold: bold, language: language)
            .build(
                dashboard: dashboard(expenseCount: expenseCount), payments: [],
                userName: "Konrad Zielinski", generatedAt: today)
    }

    @Test("The font parses and maps Polish characters to glyphs")
    func fontMapping() throws {
        let (regular, _) = try fonts()

        // Every Polish diacritic must resolve to a real glyph, not the missing-glyph box.
        for scalar in "ąćęłńóśźżĄĆĘŁŃÓŚŹŻ".unicodeScalars {
            #expect(regular.glyph(for: scalar) != 0, "no glyph for \(scalar)")
        }
        #expect(regular.glyph(for: "A") != 0)
        #expect(regular.advance(forGlyph: regular.glyph(for: "A")) > 0)
        #expect(regular.width(of: "Prąd", size: 10) > 0)
    }

    @Test("Output is a structurally complete PDF")
    func structure() throws {
        let data = try build(expenseCount: 5)
        let text = String(decoding: data, as: UTF8.self)

        #expect(data.starts(with: Array("%PDF-".utf8)))
        #expect(text.contains("/Type /Catalog"))
        #expect(text.contains("xref"))
        #expect(text.contains("trailer"))
        #expect(text.hasSuffix("%%EOF"))
    }

    @Test("The font is embedded, with a reverse mapping for copyable text")
    func embedsFont() throws {
        let text = String(decoding: try build(expenseCount: 3), as: UTF8.self)
        #expect(text.contains("/FontFile2"))
        #expect(text.contains("/Subtype /CIDFontType2"))
        #expect(text.contains("/Encoding /Identity-H"))
        #expect(text.contains("/ToUnicode"))
    }

    @Test("Long lists break across pages")
    func pagination() throws {
        let onePage = String(decoding: try build(expenseCount: 5), as: UTF8.self)
        #expect(pageCount(in: onePage) == 1)

        let many = String(decoding: try build(expenseCount: 90), as: UTF8.self)
        #expect(pageCount(in: many) > 1)
    }

    @Test("Both languages produce output")
    func languages() throws {
        #expect(try build(expenseCount: 3, language: .pl).count > 1000)
        #expect(try build(expenseCount: 3, language: .en).count > 1000)
    }

    @Test("Columns never run past the printable width")
    func columnsFitThePage() throws {
        let (regular, bold) = try fonts()
        let builder = PDFReportBuilder(regular: regular, bold: bold, language: .pl)

        let columns: [PDFReportBuilder.Column] = [
            .init(title: "Nazwa", alignment: .left),
            .init(title: "Kwota", alignment: .right),
            .init(title: "Status", alignment: .left),
        ]
        // A row far wider than the page, to force the shrinking path.
        let rows = [[String(repeating: "bardzo długa nazwa ", count: 12), "1 234,56 zł", "NADCHODZĄCE"]]

        let widths = builder.columnWidths(for: columns, rows: rows)
        #expect(widths.reduce(0, +) <= builder.contentWidth + 0.01)
        #expect(widths.allSatisfy { $0 > 0 })
    }

    private func pageCount(in pdf: String) -> Int {
        pdf.components(separatedBy: "/Type /Page ").count - 1
    }
}
