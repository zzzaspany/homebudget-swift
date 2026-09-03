import Foundation

/// Just enough of a TrueType file to embed it in a PDF.
///
/// A PDF that shows Polish text needs the font itself embedded, plus the metrics and the
/// character-to-glyph mapping so text can be positioned and copied back out. The standard
/// fourteen PDF fonts are Latin-1 only, so `ą ć ę ł ń ó ś ź ż` are not an option there.
struct TrueTypeFont {
    let data: Data
    let unitsPerEm: Int
    let numberOfGlyphs: Int
    let ascender: Int
    let descender: Int
    let boundingBox: (minX: Int, minY: Int, maxX: Int, maxY: Int)
    let italicAngle: Int = 0

    /// Advance width per glyph, already scaled to the PDF's 1000-unit em square.
    private let advances: [Int]
    /// Unicode scalar to glyph index.
    private let cmap: [UInt32: Int]

    enum ParseError: Error {
        case missingTable(String)
        case unsupportedCmap
        case truncated
    }

    init(data: Data) throws {
        self.data = data
        let reader = ByteReader(data)

        let numTables = try Int(reader.uint16(at: 4))
        var tables: [String: (offset: Int, length: Int)] = [:]
        for index in 0..<numTables {
            let entry = 12 + index * 16
            let tag = try reader.string(at: entry, length: 4)
            tables[tag] = (try Int(reader.uint32(at: entry + 8)), try Int(reader.uint32(at: entry + 12)))
        }

        guard let head = tables["head"] else { throw ParseError.missingTable("head") }
        guard let hhea = tables["hhea"] else { throw ParseError.missingTable("hhea") }
        guard let maxp = tables["maxp"] else { throw ParseError.missingTable("maxp") }
        guard let hmtx = tables["hmtx"] else { throw ParseError.missingTable("hmtx") }
        guard let cmapTable = tables["cmap"] else { throw ParseError.missingTable("cmap") }

        unitsPerEm = try Int(reader.uint16(at: head.offset + 18))
        boundingBox = (
            try Int(reader.int16(at: head.offset + 36)),
            try Int(reader.int16(at: head.offset + 38)),
            try Int(reader.int16(at: head.offset + 40)),
            try Int(reader.int16(at: head.offset + 42))
        )
        ascender = try Int(reader.int16(at: hhea.offset + 4))
        descender = try Int(reader.int16(at: hhea.offset + 6))
        numberOfGlyphs = try Int(reader.uint16(at: maxp.offset + 4))

        let metricCount = try Int(reader.uint16(at: hhea.offset + 34))
        let scale = 1000.0 / Double(unitsPerEm)
        var widths: [Int] = []
        widths.reserveCapacity(numberOfGlyphs)
        var lastAdvance = 0
        for glyph in 0..<numberOfGlyphs {
            if glyph < metricCount {
                lastAdvance = try Int(reader.uint16(at: hmtx.offset + glyph * 4))
            }
            // Glyphs past the metric table all share the final advance width.
            widths.append(Int((Double(lastAdvance) * scale).rounded()))
        }
        advances = widths

        cmap = try Self.parseCmap(reader: reader, offset: cmapTable.offset)
    }

    init(path: String) throws {
        try self.init(data: Data(contentsOf: URL(fileURLWithPath: path)))
    }

    func glyph(for scalar: Unicode.Scalar) -> Int {
        cmap[scalar.value] ?? 0
    }

    func advance(forGlyph glyph: Int) -> Int {
        glyph >= 0 && glyph < advances.count ? advances[glyph] : 0
    }

    /// Glyph indices for a string, in order, ready for Identity-H encoding.
    func glyphs(for text: String) -> [Int] {
        text.unicodeScalars.map { glyph(for: $0) }
    }

    /// Width of a string at a given point size.
    func width(of text: String, size: Double) -> Double {
        let units = glyphs(for: text).reduce(0) { $0 + advance(forGlyph: $1) }
        return Double(units) * size / 1000
    }

    /// Every glyph the text uses, so only those need widths written into the PDF.
    func usedGlyphs(in texts: [String]) -> [Int: Unicode.Scalar] {
        var used: [Int: Unicode.Scalar] = [:]
        for text in texts {
            for scalar in text.unicodeScalars {
                used[glyph(for: scalar)] = scalar
            }
        }
        return used
    }

    // MARK: - Character map

    private static func parseCmap(reader: ByteReader, offset: Int) throws -> [UInt32: Int] {
        let tableCount = try Int(reader.uint16(at: offset + 2))

        // Prefer a Windows BMP table, then any Unicode one.
        var chosen: Int?
        for index in 0..<tableCount {
            let record = offset + 4 + index * 8
            let platform = try reader.uint16(at: record)
            let encoding = try reader.uint16(at: record + 2)
            let subtable = offset + Int(try reader.uint32(at: record + 4))

            if platform == 3 && encoding == 1 { chosen = subtable; break }
            if platform == 0 && chosen == nil { chosen = subtable }
        }

        guard let subtable = chosen, try reader.uint16(at: subtable) == 4 else {
            throw ParseError.unsupportedCmap
        }
        return try parseFormat4(reader: reader, offset: subtable)
    }

    /// Format 4: the segmented mapping used for the Basic Multilingual Plane.
    private static func parseFormat4(reader: ByteReader, offset: Int) throws -> [UInt32: Int] {
        let segCount = try Int(reader.uint16(at: offset + 6)) / 2
        let endCodes = offset + 14
        let startCodes = endCodes + segCount * 2 + 2
        let idDeltas = startCodes + segCount * 2
        let idRangeOffsets = idDeltas + segCount * 2

        var map: [UInt32: Int] = [:]
        for segment in 0..<segCount {
            let end = try Int(reader.uint16(at: endCodes + segment * 2))
            let start = try Int(reader.uint16(at: startCodes + segment * 2))
            let delta = try Int(reader.int16(at: idDeltas + segment * 2))
            let rangeOffsetPosition = idRangeOffsets + segment * 2
            let rangeOffset = try Int(reader.uint16(at: rangeOffsetPosition))

            guard start <= end, end != 0xFFFF || start != 0xFFFF else { continue }

            for code in start...end {
                let glyph: Int
                if rangeOffset == 0 {
                    glyph = (code + delta) & 0xFFFF
                } else {
                    let position = rangeOffsetPosition + rangeOffset + (code - start) * 2
                    guard let raw = try? reader.uint16(at: position), raw != 0 else { continue }
                    glyph = (Int(raw) + delta) & 0xFFFF
                }
                if glyph != 0 { map[UInt32(code)] = glyph }
            }
        }
        return map
    }
}

/// Big-endian reads with bounds checking, which is how TrueType stores everything.
private struct ByteReader {
    let data: Data

    init(_ data: Data) { self.data = data }

    private func byte(at index: Int) throws -> UInt8 {
        guard index >= 0, index < data.count else { throw TrueTypeFont.ParseError.truncated }
        return data[data.startIndex + index]
    }

    func uint16(at offset: Int) throws -> UInt16 {
        UInt16(try byte(at: offset)) << 8 | UInt16(try byte(at: offset + 1))
    }

    func int16(at offset: Int) throws -> Int16 {
        Int16(bitPattern: try uint16(at: offset))
    }

    func uint32(at offset: Int) throws -> UInt32 {
        (UInt32(try uint16(at: offset)) << 16) | UInt32(try uint16(at: offset + 2))
    }

    func string(at offset: Int, length: Int) throws -> String {
        var scalars = ""
        for index in 0..<length {
            scalars.append(Character(Unicode.Scalar(try byte(at: offset + index))))
        }
        return scalars
    }
}
