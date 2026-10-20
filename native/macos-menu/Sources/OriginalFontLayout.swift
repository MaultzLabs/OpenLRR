import Foundation

/// Portable layout for the original Gods98 bitmap-font print routine.
/// Mirrors Font_VPrintF2 / Font_OutputChar in engine/drawing/Fonts.cpp:
/// 10x19 glyph cells starting at byte 32, tab stops based on the width of
/// the first glyph cell, newlines, and byte 203's non-advancing overlay.
/// The English retail game's text is 8-bit Windows text, not UTF-8 glyph IDs.
struct OriginalFontLayout {
    struct Glyph {
        let index: Int
        let x: Int
        let y: Int
    }

    let glyphs: [Glyph]
    let width: Int
    let height: Int
    let lineCount: Int

    static func make(_ text: String, characterWidths: [Int], lineHeight: Int) -> Self? {
        guard characterWidths.count == 190,
              characterWidths.allSatisfy({ (1...4096).contains($0) }),
              (1...4096).contains(lineHeight),
              let bytes = text.data(using: .windowsCP1252), bytes.count <= 4096 else {
            return nil
        }
        let tabWidth = characterWidths[0] * 8
        var x = 0, y = 0, maximumWidth = 0, lines = 1
        var glyphs: [Glyph] = []
        glyphs.reserveCapacity(bytes.count)
        for byte in bytes {
            switch byte {
            case 10: // '\n'
                maximumWidth = max(maximumWidth, x)
                x = 0
                y += lineHeight
                lines += 1
            case 9: // '\t'
                x += tabWidth - (x % tabWidth)
            default:
                let index = Int(byte) - 32
                guard (0..<characterWidths.count).contains(index) else { continue }
                glyphs.append(Glyph(index: index, x: x, y: y))
                // The retail engine draws glyph 203 without advancing x.
                if byte != 203 { x += characterWidths[index] }
            }
        }
        return Self(glyphs: glyphs, width: max(maximumWidth, x),
                    height: lines * lineHeight, lineCount: lines)
    }
}
