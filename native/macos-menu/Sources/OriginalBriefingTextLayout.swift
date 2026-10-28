import Foundation

/// The non-overlay TextWindow_Update path used by Objective.cpp:1070–1077.
/// This is deliberately separate from Font_VPrintF layout: TextWindow tabs
/// have zero width, line-break spaces remain in the drawn text, and overflowing
/// windows display their last fitting whole lines. Only synthetic geometry is
/// produced; the caller draws with the user's original bitmap font.
enum OriginalBriefingTextLayout {
    struct Line {
        /// Original bytes for this line, including spaces/tabs but excluding
        /// its newline delimiter. Use `layout` to draw: ordinary font layout
        /// would incorrectly turn these tabs into eight-space tab stops.
        let text: String
        let x: Int
        let y: Int
        let layout: OriginalFontLayout
    }

    static func make(text: String, characterWidths: [Int], lineHeight: Int,
                     width: Int, height: Int, centered: Bool) -> [Line]? {
        guard characterWidths.count == 190,
              characterWidths.allSatisfy({ (1...4096).contains($0) }),
              (1...4096).contains(lineHeight), (1...8192).contains(width),
              (0...8192).contains(height),
              let encoded = text.data(using: .windowsCP1252), encoded.count <= 4096,
              encoded.allSatisfy({ $0 >= 32 || $0 == 9 || $0 == 10 || $0 == 7 }) else { return nil }
        let bytes = Array(encoded.prefix { $0 != 7 })
        var starts = [0], widths: [Int] = []
        var currentWidth = 0, wordWidth = 0
        var pendingBreak = 0, pendingWidth = 0

        // Mirror the line list and width list separately. At a soft break,
        // TextWindow records the width BEFORE the separating whitespace but
        // retains that whitespace in the preceding line's character range.
        // Its wordWidth also includes the separator's advance. Recomputing
        // widths from trimmed strings changes original centered placement.
        for (index, byte) in bytes.enumerated() {
            if byte == 10 {
                starts.append(index + 1)
                widths.append(currentWidth)
                currentWidth = 0
                wordWidth = 0
                continue
            }
            if byte == 32 || byte == 9 {
                pendingBreak = index + 1
                pendingWidth = currentWidth
                wordWidth = 0
            }
            let glyph = Int(byte) - 32
            let advance = byte == 203 ? 0 :
                ((0..<190).contains(glyph) ? characterWidths[glyph] : 0)
            currentWidth += advance
            wordWidth += advance
            if currentWidth >= width {
                if wordWidth >= width {
                    // Even an oversized first glyph creates an empty line in
                    // the original. Preserve that rather than losing a glyph.
                    starts.append(index)
                    widths.append(currentWidth - advance)
                    currentWidth = advance
                    wordWidth = advance
                } else {
                    starts.append(pendingBreak)
                    widths.append(pendingWidth)
                    currentWidth = wordWidth
                }
            }
        }
        starts.append(bytes.count)
        widths.append(currentWidth)

        let visibleCount = height / lineHeight
        guard visibleCount > 0 else { return [] }
        let firstVisible = max(0, widths.count - visibleCount)
        var lines: [Line] = []
        for index in firstVisible..<widths.count {
            var lineBytes = Array(bytes[starts[index]..<starts[index + 1]])
            if lineBytes.last == 10 { lineBytes.removeLast() }
            guard let lineText = String(data: Data(lineBytes), encoding: .windowsCP1252) else { return nil }
            var glyphs: [OriginalFontLayout.Glyph] = []
            var pen = 0, caret = false
            for byte in lineBytes {
                if byte == 203 { caret = true; continue }
                let glyph = Int(byte) - 32
                if (0..<190).contains(glyph) {
                    glyphs.append(.init(index: glyph, x: pen, y: 0))
                }
                // TextWindow.cpp:263–295 draws the following character first,
                // then the byte-203 caret four pixels LEFT of the same pen.
                if caret {
                    glyphs.append(.init(index: 203 - 32, x: pen - 4, y: 0))
                    caret = false
                }
                if (0..<190).contains(glyph) { pen += characterWidths[glyph] }
            }
            if caret { glyphs.append(.init(index: 203 - 32, x: pen - 4, y: 0)) }
            let layout = OriginalFontLayout(glyphs: glyphs, width: widths[index],
                                            height: lineHeight, lineCount: 1)
            // Swift integer division, like the source's cast, truncates toward
            // zero (including an oversized line's negative centering offset).
            lines.append(Line(text: lineText,
                              x: centered ? (width - widths[index]) / 2 : 0,
                              y: (index - firstVisible) * lineHeight, layout: layout))
        }
        return lines
    }
}
