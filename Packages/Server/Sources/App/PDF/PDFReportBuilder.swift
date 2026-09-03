import Foundation
import HomeBudgetCore

/// Lays the budget report out onto A4 pages.
///
/// The footer says "page N of M", so the page count has to be known before anything is written.
/// Layout therefore runs first, collecting drawing commands per page, and the content streams are
/// emitted afterwards.
struct PDFReportBuilder {
    let regular: TrueTypeFont
    let bold: TrueTypeFont
    let language: Language

    // A4 in points, with the same 54pt margin the Python report used.
    static let pageWidth = 595.28
    static let pageHeight = 841.89
    static let margin = 54.0

    var contentWidth: Double { Self.pageWidth - Self.margin * 2 }

    /// Table text is a point smaller than the surrounding copy. At 9pt the expense table's six
    /// columns needed marginally more room than A4 portrait allows, and the overflow landed on
    /// whichever column happened to be last.
    static let tableFontSize = 8.0

    // MARK: - Drawing commands

    enum Command {
        case text(String, x: Double, y: Double, size: Double, bold: Bool, color: Color)
        case rect(x: Double, y: Double, width: Double, height: Double, color: Color)
        case line(x1: Double, y1: Double, x2: Double, y2: Double, color: Color)
    }

    struct Color {
        let red: Double, green: Double, blue: Double

        static let ink = Color(red: 0.06, green: 0.09, blue: 0.16)
        static let body = Color(red: 0.2, green: 0.25, blue: 0.33)
        static let muted = Color(red: 0.39, green: 0.45, blue: 0.55)
        static let rule = Color(red: 0.89, green: 0.91, blue: 0.94)
        static let headerFill = Color(red: 0.06, green: 0.09, blue: 0.16)
        static let subHeaderFill = Color(red: 0.2, green: 0.25, blue: 0.33)
        static let panel = Color(red: 0.97, green: 0.98, blue: 0.99)
        static let white = Color(red: 1, green: 1, blue: 1)
    }

    final class Layout {
        var pages: [[Command]] = [[]]
        var cursor: Double

        init(startY: Double) { cursor = startY }

        var current: Int { pages.count - 1 }

        func append(_ command: Command) {
            pages[current].append(command)
        }

        func newPage(startY: Double) {
            pages.append([])
            cursor = startY
        }
    }

    // MARK: - Report

    func build(dashboard: Dashboard, payments: [PaymentRecord], userName: String, generatedAt: CalendarDate) -> Data {
        let layout = Layout(startY: Self.pageHeight - Self.margin)

        titleBlock(layout, userName: userName, generatedAt: generatedAt)
        kpiSection(layout, kpis: dashboard.kpis)
        expenseSection(layout, expenses: dashboard.expenses)
        paymentSection(layout, payments: Array(payments.prefix(25)))

        return render(layout)
    }

    private func titleBlock(_ layout: Layout, userName: String, generatedAt: CalendarDate) {
        let title = language == .pl
            ? "HOMEBUDGET — RAPORT FINANSOWY DOMU"
            : "HOMEBUDGET — HOME FINANCIAL REPORT"
        layout.append(.text(title, x: Self.margin, y: layout.cursor, size: 18, bold: true, color: .ink))
        layout.cursor -= 22

        let generated = language == .pl ? "Wygenerowano" : "Generated"
        let user = language == .pl ? "Użytkownik" : "User"
        layout.append(
            .text(
                "\(generated): \(Localization.dateLabel(generatedAt, language: language))  ·  \(user): \(userName)",
                x: Self.margin, y: layout.cursor, size: 10, bold: false, color: .muted))
        layout.cursor -= 28
    }

    private func kpiSection(_ layout: Layout, kpis: Dashboard.KPIs) {
        sectionHeading(layout, language == .pl ? "Podsumowanie" : "Summary")

        let rows = [
            (language == .pl ? "Średniomiesięczny budżet" : "Average monthly budget", kpis.proRatedMonthly),
            (language == .pl ? "Miesięczna rezerwa" : "Monthly reserve", kpis.sinkingFundTotal),
            (language == .pl ? "Zobowiązania miesięczne" : "Monthly dues", kpis.monthlyTotal),
            (language == .pl ? "Zobowiązania roczne" : "Yearly dues", kpis.yearlyTotal),
        ]

        for (label, value) in rows {
            ensureSpace(layout, needed: 20)
            layout.append(
                .rect(
                    x: Self.margin, y: layout.cursor - 5, width: contentWidth, height: 19,
                    color: .panel))
            layout.append(
                .text(label, x: Self.margin + 8, y: layout.cursor, size: 10, bold: false, color: .body))
            let amount = NumberFormatting.currency(value, language: language)
            let width = regular.width(of: amount, size: 10)
            layout.append(
                .text(
                    amount, x: Self.pageWidth - Self.margin - 8 - width, y: layout.cursor,
                    size: 10, bold: true, color: .ink))
            layout.cursor -= 21
        }
        layout.cursor -= 14
    }

    private func expenseSection(_ layout: Layout, expenses: [Dashboard.ExpenseSummary]) {
        sectionHeading(layout, language == .pl ? "Wykaz wydatków cyklicznych" : "Recurring expenses")

        let columns: [Column] = [
            .init(title: language == .pl ? "Nazwa" : "Name", alignment: .left),
            .init(title: language == .pl ? "Kwota" : "Amount", alignment: .right),
            .init(title: language == .pl ? "Cykl" : "Cycle", alignment: .left),
            .init(title: language == .pl ? "Termin" : "Due", alignment: .left),
            .init(title: language == .pl ? "Kategoria" : "Category", alignment: .left),
            .init(title: "Status", alignment: .left),
        ]

        table(
            layout, columns: columns, headerColor: .headerFill,
            rows: expenses.map { summary in
                let expense = summary.expense
                return [
                    expense.name,
                    NumberFormatting.currency(expense.amount, language: language),
                    expense.frequency.label(language: language),
                    summary.dueDate.map { Localization.dateLabel($0, language: language) } ?? "—",
                    Localization.category(expense.category, language: language),
                    summary.status.reportLabel(language: language),
                ]
            })
        layout.cursor -= 14
    }

    private func paymentSection(_ layout: Layout, payments: [PaymentRecord]) {
        guard !payments.isEmpty else { return }
        sectionHeading(layout, language == .pl ? "Ostatnie wpłaty" : "Recent payments")

        let columns: [Column] = [
            .init(title: language == .pl ? "Nazwa" : "Name", alignment: .left),
            .init(title: language == .pl ? "Kategoria" : "Category", alignment: .left),
            .init(title: language == .pl ? "Okres" : "Period", alignment: .left),
            .init(title: language == .pl ? "Zapłacono" : "Paid", alignment: .right),
            .init(title: language == .pl ? "Data" : "Date", alignment: .left),
            .init(title: language == .pl ? "Kto" : "By", alignment: .left),
        ]

        table(
            layout, columns: columns, headerColor: .subHeaderFill,
            rows: payments.map { payment in
                [
                    payment.expenseName,
                    Localization.category(payment.category, language: language),
                    Localization.periodLabel(payment.period, language: language),
                    NumberFormatting.currency(payment.amountPaid, language: language),
                    Localization.dateLabel(payment.datePaid, language: language),
                    payment.paidBy,
                ]
            })
    }

    // MARK: - Building blocks

    struct Column {
        enum Alignment { case left, right }
        let title: String
        let alignment: Alignment

        init(title: String, alignment: Alignment) {
            self.title = title
            self.alignment = alignment
        }
    }

    /// Sizes each column to the widest thing it actually holds.
    ///
    /// Guessing widths meant "Miesięczny" and "NADCHODZĄCE" were clipped while the amount column
    /// sat half empty. Measuring the content instead gives every column what it needs; only when
    /// the total exceeds the page does anything shrink, and then in proportion to its slack, so
    /// the roomiest columns give up the most.
    func columnWidths(for columns: [Column], rows: [[String]]) -> [Double] {
        let padding = 10.0
        let natural = columns.enumerated().map { index, column -> Double in
            let header = bold.width(of: column.title, size: Self.tableFontSize)
            let widest = rows.reduce(0.0) { longest, row in
                guard index < row.count else { return longest }
                return max(longest, regular.width(of: row[index], size: Self.tableFontSize))
            }
            return max(header, widest) + padding
        }

        let total = natural.reduce(0, +)
        guard total > contentWidth else {
            // Spare room goes to the first column, which holds the names.
            var widths = natural
            widths[0] += contentWidth - total
            return widths
        }

        let minimum = columns.map { bold.width(of: $0.title, size: Self.tableFontSize) + padding }
        let slack = zip(natural, minimum).map { $0 - $1 }
        let slackTotal = slack.reduce(0, +)
        guard slackTotal > 0 else { return natural }

        let overflow = total - contentWidth
        return zip(natural, slack).map { width, available in
            width - overflow * available / slackTotal
        }
    }

    private func sectionHeading(_ layout: Layout, _ title: String) {
        ensureSpace(layout, needed: 34)
        layout.append(.text(title, x: Self.margin, y: layout.cursor, size: 12, bold: true, color: .ink))
        layout.cursor -= 6
        layout.append(
            .line(
                x1: Self.margin, y1: layout.cursor, x2: Self.pageWidth - Self.margin,
                y2: layout.cursor, color: .rule))
        layout.cursor -= 16
    }

    private func table(_ layout: Layout, columns: [Column], headerColor: Color, rows: [[String]]) {
        let widths = columnWidths(for: columns, rows: rows)
        tableHeader(layout, columns: columns, widths: widths, color: headerColor)

        for row in rows {
            if layout.cursor < Self.margin + 40 {
                layout.newPage(startY: Self.pageHeight - Self.margin)
                tableHeader(layout, columns: columns, widths: widths, color: headerColor)
            }

            var x = Self.margin
            for (index, column) in columns.enumerated() {
                let value = index < row.count ? row[index] : ""
                let text = truncate(value, to: widths[index] - 10, size: Self.tableFontSize)
                let offset = column.alignment == .right
                    ? widths[index] - 5 - regular.width(of: text, size: Self.tableFontSize)
                    : 5
                layout.append(
                    .text(text, x: x + offset, y: layout.cursor, size: Self.tableFontSize, bold: false, color: .body))
                x += widths[index]
            }

            layout.cursor -= 5
            layout.append(
                .line(
                    x1: Self.margin, y1: layout.cursor, x2: Self.margin + contentWidth,
                    y2: layout.cursor, color: .rule))
            layout.cursor -= 13
        }
    }

    private func tableHeader(_ layout: Layout, columns: [Column], widths: [Double], color: Color) {
        layout.append(
            .rect(x: Self.margin, y: layout.cursor - 5, width: contentWidth, height: 18, color: color))

        var x = Self.margin
        for (index, column) in columns.enumerated() {
            let offset = column.alignment == .right
                ? widths[index] - 5 - bold.width(of: column.title, size: Self.tableFontSize)
                : 5
            layout.append(
                .text(column.title, x: x + offset, y: layout.cursor, size: Self.tableFontSize, bold: true, color: .white))
            x += widths[index]
        }
        layout.cursor -= 20
    }

    private func ensureSpace(_ layout: Layout, needed: Double) {
        if layout.cursor - needed < Self.margin + 30 {
            layout.newPage(startY: Self.pageHeight - Self.margin)
        }
    }

    /// Trims a value to the column width, with an ellipsis, so text never runs into its neighbour.
    private func truncate(_ text: String, to width: Double, size: Double) -> String {
        guard regular.width(of: text, size: size) > width else { return text }
        var characters = Array(text)
        while !characters.isEmpty,
            regular.width(of: String(characters) + "…", size: size) > width
        {
            characters.removeLast()
        }
        return String(characters) + "…"
    }

    // MARK: - Emitting

    private func render(_ layout: Layout) -> Data {
        let document = PDFDocument()
        let pagesObject = document.reserve()

        let footers = layout.pages.indices.map { footerText(page: $0 + 1, of: layout.pages.count) }
        let allText = layout.pages.flatMap { page in
            page.compactMap { command -> String? in
                if case .text(let value, _, _, _, _, _) = command { return value }
                return nil
            }
        } + footers

        let regularObject = PDFFontEmbedder(font: regular, baseName: "DejaVuSans")
            .embed(in: document, texts: allText)
        let boldObject = PDFFontEmbedder(font: bold, baseName: "DejaVuSans-Bold")
            .embed(in: document, texts: allText)

        var pageObjects: [Int] = []
        for (index, commands) in layout.pages.enumerated() {
            var stream = ""
            for command in commands {
                stream += instruction(command)
            }
            stream += footer(page: index + 1, of: layout.pages.count)

            let content = document.addStream(content: stream)
            let page = document.add(
                """
                << /Type /Page /Parent \(pagesObject) 0 R \
                /MediaBox [0 0 \(fmt(Self.pageWidth)) \(fmt(Self.pageHeight))] \
                /Resources << /Font << /F1 \(regularObject) 0 R /F2 \(boldObject) 0 R >> >> \
                /Contents \(content) 0 R >>
                """)
            pageObjects.append(page)
        }

        document.define(
            pagesObject,
            """
            << /Type /Pages /Count \(pageObjects.count) \
            /Kids [\(pageObjects.map { "\($0) 0 R" }.joined(separator: " "))] >>
            """)

        let catalog = document.add("<< /Type /Catalog /Pages \(pagesObject) 0 R >>")
        return document.build(rootObject: catalog)
    }

    private func instruction(_ command: Command) -> String {
        switch command {
        case .text(let value, let x, let y, let size, let isBold, let color):
            let font = isBold ? bold : regular
            return """
                BT /\(isBold ? "F2" : "F1") \(fmt(size)) Tf \
                \(fmt(color.red)) \(fmt(color.green)) \(fmt(color.blue)) rg \
                \(fmt(x)) \(fmt(y)) Td \(PDFDocument.glyphString(value, font: font)) Tj ET

                """
        case .rect(let x, let y, let width, let height, let color):
            return """
                \(fmt(color.red)) \(fmt(color.green)) \(fmt(color.blue)) rg \
                \(fmt(x)) \(fmt(y)) \(fmt(width)) \(fmt(height)) re f

                """
        case .line(let x1, let y1, let x2, let y2, let color):
            return """
                \(fmt(color.red)) \(fmt(color.green)) \(fmt(color.blue)) RG 0.5 w \
                \(fmt(x1)) \(fmt(y1)) m \(fmt(x2)) \(fmt(y2)) l S

                """
        }
    }

    private func footerText(page: Int, of total: Int) -> String {
        language == .pl ? "Strona \(page) z \(total)" : "Page \(page) of \(total)"
    }

    private func footer(page: Int, of total: Int) -> String {
        let caption = language == .pl
            ? "HomeBudget — raport kosztów utrzymania domu"
            : "HomeBudget — home maintenance expense report"
        let counter = footerText(page: page, of: total)
        let counterWidth = regular.width(of: counter, size: 8)

        return instruction(
            .text(caption, x: Self.margin, y: 30, size: 8, bold: false, color: .muted))
            + instruction(
                .text(
                    counter, x: Self.pageWidth - Self.margin - counterWidth, y: 30, size: 8,
                    bold: false, color: .muted))
    }

    private func fmt(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }
}
