import Foundation

/// A minimal PDF writer: indirect objects, streams, a cross-reference table and an embedded font.
///
/// Written by hand rather than pulled from a library because no maintained pure-Swift PDF package
/// covers embedded Unicode fonts on Linux, and rendering HTML through a headless browser would
/// have meant running a second, non-Swift service alongside the app.
final class PDFDocument {
    /// Objects in order; index + 1 is the object number.
    private var objects: [Data] = []

    /// Reserves an object number to be filled in later, for forward references.
    func reserve() -> Int {
        objects.append(Data())
        return objects.count
    }

    @discardableResult
    func define(_ number: Int, _ body: String) -> Int {
        objects[number - 1] = Data(body.utf8)
        return number
    }

    @discardableResult
    func add(_ body: String) -> Int {
        let number = reserve()
        return define(number, body)
    }

    /// A stream object. Streams are written uncompressed: these reports are small, and it keeps
    /// the output inspectable when something looks wrong.
    @discardableResult
    func addStream(dictionary: String = "", content: Data) -> Int {
        let number = reserve()
        var body = Data("<< \(dictionary) /Length \(content.count) >>\nstream\n".utf8)
        body.append(content)
        body.append(Data("\nendstream".utf8))
        objects[number - 1] = body
        return number
    }

    @discardableResult
    func addStream(dictionary: String = "", content: String) -> Int {
        addStream(dictionary: dictionary, content: Data(content.utf8))
    }

    /// Serialises the file, with the cross-reference table the trailer points at.
    func build(rootObject: Int) -> Data {
        var output = Data("%PDF-1.7\n".utf8)
        // A comment of high bytes marks the file as binary for tools that transfer it.
        output.append(contentsOf: [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])

        var offsets: [Int] = []
        for (index, object) in objects.enumerated() {
            offsets.append(output.count)
            output.append(Data("\(index + 1) 0 obj\n".utf8))
            output.append(object)
            output.append(Data("\nendobj\n".utf8))
        }

        let xrefOffset = output.count
        output.append(Data("xref\n0 \(objects.count + 1)\n".utf8))
        output.append(Data("0000000000 65535 f \n".utf8))
        for offset in offsets {
            let padded = String(format: "%010d", offset)
            output.append(Data("\(padded) 00000 n \n".utf8))
        }

        output.append(
            Data(
                """
                trailer
                << /Size \(objects.count + 1) /Root \(rootObject) 0 R >>
                startxref
                \(xrefOffset)
                %%EOF
                """.utf8))
        return output
    }

    // MARK: - Text encoding

    /// Escapes a string for a PDF literal, used for metadata rather than page text.
    static func literal(_ text: String) -> String {
        var escaped = ""
        for character in text.unicodeScalars {
            switch character {
            case "(", ")", "\\": escaped.append("\\\(character)")
            default: escaped.unicodeScalars.append(character)
            }
        }
        return "(\(escaped))"
    }

    /// Text as a hex string of glyph indices, which is what Identity-H encoding expects.
    static func glyphString(_ text: String, font: TrueTypeFont) -> String {
        let hex = font.glyphs(for: text)
            .map { String(format: "%04X", $0) }
            .joined()
        return "<\(hex)>"
    }
}

/// Registers an embedded TrueType font and writes the objects a PDF needs to use it.
struct PDFFontEmbedder {
    let font: TrueTypeFont
    let baseName: String

    /// Adds the font objects and returns the number of the top-level font object.
    ///
    /// `texts` supplies every string the document will draw, so only the glyphs actually used get
    /// a width entry and a reverse mapping.
    func embed(in document: PDFDocument, texts: [String]) -> Int {
        let used = font.usedGlyphs(in: texts)
        let fontFile = document.addStream(
            dictionary: "/Length1 \(font.data.count)", content: font.data)

        let descriptor = document.add(
            """
            << /Type /FontDescriptor /FontName /\(baseName) /Flags 4 \
            /FontBBox [\(scaled(font.boundingBox.minX)) \(scaled(font.boundingBox.minY)) \
            \(scaled(font.boundingBox.maxX)) \(scaled(font.boundingBox.maxY))] \
            /ItalicAngle \(font.italicAngle) /Ascent \(scaled(font.ascender)) \
            /Descent \(scaled(font.descender)) /CapHeight \(scaled(font.ascender)) \
            /StemV 80 /FontFile2 \(fontFile) 0 R >>
            """)

        let descendant = document.add(
            """
            << /Type /Font /Subtype /CIDFontType2 /BaseFont /\(baseName) \
            /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> \
            /FontDescriptor \(descriptor) 0 R /DW 1000 /W [\(widthArray(used.keys.sorted()))] \
            /CIDToGIDMap /Identity >>
            """)

        let toUnicode = document.addStream(content: toUnicodeCMap(used))

        return document.add(
            """
            << /Type /Font /Subtype /Type0 /BaseFont /\(baseName) /Encoding /Identity-H \
            /DescendantFonts [\(descendant) 0 R] /ToUnicode \(toUnicode) 0 R >>
            """)
    }

    private func scaled(_ value: Int) -> Int {
        Int((Double(value) * 1000 / Double(font.unitsPerEm)).rounded())
    }

    /// Widths in the compact `[cid [w] cid [w] …]` form.
    private func widthArray(_ glyphs: [Int]) -> String {
        glyphs.map { "\($0) [\(font.advance(forGlyph: $0))]" }.joined(separator: " ")
    }

    /// Maps glyph indices back to characters, so selecting and copying text from the PDF works.
    private func toUnicodeCMap(_ used: [Int: Unicode.Scalar]) -> String {
        let entries = used.sorted { $0.key < $1.key }
            .map { glyph, scalar in
                String(format: "<%04X> <%04X>", glyph, scalar.value)
            }

        // The spec caps a single bfchar block at 100 entries.
        let blocks = stride(from: 0, to: entries.count, by: 100).map { start -> String in
            let slice = entries[start..<min(start + 100, entries.count)]
            return "\(slice.count) beginbfchar\n\(slice.joined(separator: "\n"))\nendbfchar"
        }

        return """
            /CIDInit /ProcSet findresource begin
            12 dict begin
            begincmap
            /CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def
            /CMapName /Adobe-Identity-UCS def
            /CMapType 2 def
            1 begincodespacerange
            <0000> <FFFF>
            endcodespacerange
            \(blocks.joined(separator: "\n"))
            endcmap
            CMapName currentdict /CMap defineresource pop
            end
            end
            """
    }
}
