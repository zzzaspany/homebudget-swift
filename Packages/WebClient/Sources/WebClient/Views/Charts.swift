#if canImport(WASILibc)
    import WASILibc
#elseif canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import HomeBudgetCore
import JavaScriptKit

/// Charts drawn as inline SVG built in Swift.
///
/// The Python app used Chart.js, which meant rebuilding both charts from scratch on every theme
/// change to recolour them. Here the shapes are plain elements, so the stylesheet handles theming
/// and there is no JavaScript charting dependency to load.
@MainActor
enum Charts {
    /// The palette from the Python app, kept so the two look like the same product.
    static let palette = [
        "#6366F1", "#06B6D4", "#10B981", "#F59E0B",
        "#EF4444", "#3B82F6", "#EC4899", "#8B5CF6",
    ]

    static func color(at index: Int) -> String {
        palette[index % palette.count]
    }

    // MARK: - Category doughnut

    static func doughnut(_ shares: [Dashboard.CategoryShare], language: Language) -> JSObject {
        let total = shares.reduce(0) { $0 + $1.proratedAmount }
        let container = DOM.element("div", class: "chart")

        guard total > 0 else {
            return container.appending(
                DOM.element("p", class: "muted", text: UIString.emptyExpenses(language)))
        }

        let size = 200.0
        let centre = size / 2
        let outer = 92.0
        let inner = 64.0

        let svg = svgElement("svg")
        svg.attribute("viewBox", "0 0 \(fmt(size)) \(fmt(size))")
        svg.attribute("class", "doughnut")
        svg.attribute("role", "img")

        var startAngle = -90.0
        for (index, share) in shares.enumerated() {
            let sweep = share.proratedAmount / total * 360
            // A full circle cannot be expressed as an arc; draw two rings instead.
            let path = sweep >= 359.99
                ? ringPath(centre: centre, outer: outer, inner: inner)
                : segmentPath(centre: centre, outer: outer, inner: inner, from: startAngle, to: startAngle + sweep)

            let segment = svgElement("path")
            segment.attribute("d", path)
            segment.attribute("fill", color(at: index))
            segment.attribute("class", "segment")

            let title = svgElement("title")
            title.textContent = .string(
                "\(Localization.category(share.category, language: language)): "
                    + NumberFormatting.currency(share.proratedAmount, language: language))
            segment.appending(title)

            svg.appending(segment)
            startAngle += sweep
        }

        let centreLabel = DOM.element("div", class: "doughnut-centre").appending(
            DOM.element("span", class: "muted small", text: UIString.kpiMonthlyBudget(language)),
            DOM.element("strong", text: NumberFormatting.currency(total, language: language))
        )

        let legend = DOM.element("ul", class: "legend").appending(
            shares.enumerated().map { index, share in
                let swatch = DOM.element("span", class: "swatch")
                swatch.style.background = .string(color(at: index))
                return DOM.element("li").appending(
                    swatch,
                    DOM.element(
                        "span", class: "grow",
                        text: Localization.category(share.category, language: language)),
                    DOM.element(
                        "span", class: "amount small",
                        text: NumberFormatting.currency(share.proratedAmount, language: language))
                )
            }
        )

        return container.appending(
            DOM.element("div", class: "doughnut-wrap").appending(svg, centreLabel),
            legend
        )
    }

    // MARK: - Twelve-month projection

    static func projection(_ entries: [Dashboard.ProjectionEntry], language: Language) -> JSObject {
        let container = DOM.element("div", class: "chart")
        let peak = entries.map(\.amount).max() ?? 0

        guard peak > 0 else {
            return container.appending(
                DOM.element("p", class: "muted", text: UIString.emptyExpenses(language)))
        }

        let bars = entries.map { entry -> JSObject in
            let height = entry.amount / peak * 100
            let fill = DOM.element("div", class: "bar-column-fill")
            fill.style.height = .string("\(fmt(max(height, 1)))%")
            fill.attribute(
                "title",
                Localization.projectionLabel(year: entry.year, month: entry.month, language: language)
                    + ": " + NumberFormatting.currency(entry.amount, language: language))

            return DOM.element("div", class: "bar-column").appending(
                DOM.element("div", class: "bar-track").appending(fill),
                DOM.element(
                    "span", class: "bar-label",
                    text: Localization.monthAbbreviation(entry.month, language: language))
            )
        }

        return container.appending(
            DOM.element("div", class: "bar-chart").appending(bars),
            DOM.element(
                "p", class: "muted small",
                text: "\(UIString.chartPeak(language)): \(NumberFormatting.currency(peak, language: language))")
        )
    }

    // MARK: - SVG geometry

    private static func svgElement(_ tag: String) -> JSObject {
        DOM.document.createElementNS("http://www.w3.org/2000/svg", tag).object!
    }

    /// A doughnut slice: outer arc one way, inner arc back.
    private static func segmentPath(
        centre: Double, outer: Double, inner: Double, from: Double, to: Double
    ) -> String {
        let outerStart = point(centre: centre, radius: outer, angle: from)
        let outerEnd = point(centre: centre, radius: outer, angle: to)
        let innerEnd = point(centre: centre, radius: inner, angle: to)
        let innerStart = point(centre: centre, radius: inner, angle: from)
        let largeArc = (to - from) > 180 ? 1 : 0

        return [
            "M \(fmt(outerStart.x)) \(fmt(outerStart.y))",
            "A \(fmt(outer)) \(fmt(outer)) 0 \(largeArc) 1 \(fmt(outerEnd.x)) \(fmt(outerEnd.y))",
            "L \(fmt(innerEnd.x)) \(fmt(innerEnd.y))",
            "A \(fmt(inner)) \(fmt(inner)) 0 \(largeArc) 0 \(fmt(innerStart.x)) \(fmt(innerStart.y))",
            "Z",
        ].joined(separator: " ")
    }

    /// A complete ring, for the case where one category is everything.
    private static func ringPath(centre: Double, outer: Double, inner: Double) -> String {
        """
        M \(fmt(centre - outer)) \(fmt(centre)) \
        a \(fmt(outer)) \(fmt(outer)) 0 1 0 \(fmt(outer * 2)) 0 \
        a \(fmt(outer)) \(fmt(outer)) 0 1 0 \(fmt(-outer * 2)) 0 \
        M \(fmt(centre - inner)) \(fmt(centre)) \
        a \(fmt(inner)) \(fmt(inner)) 0 1 1 \(fmt(inner * 2)) 0 \
        a \(fmt(inner)) \(fmt(inner)) 0 1 1 \(fmt(-inner * 2)) 0 Z
        """
    }

    private static func point(centre: Double, radius: Double, angle: Double) -> (x: Double, y: Double) {
        let radians = angle * Double.pi / 180
        return (centre + radius * cos(radians), centre + radius * sin(radians))
    }

    /// Trims to two decimals: SVG path data does not need more, and shorter strings keep the
    /// generated markup readable when debugging.
    private static func fmt(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        return rounded == rounded.rounded() ? "\(Int(rounded))" : "\(rounded)"
    }
}
