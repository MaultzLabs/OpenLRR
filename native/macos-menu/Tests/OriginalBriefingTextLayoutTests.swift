import Foundation

/// Synthetic widths and strings only; no retail font or objective text.
/// swiftc Sources/OriginalFontLayout.swift Sources/OriginalBriefingTextLayout.swift \
///   Tests/OriginalBriefingTextLayoutTests.swift -o /tmp/openlrr-briefing-layout-test
@main struct OriginalBriefingTextLayoutTests {
    static let widths: [Int] = {
        var result = [Int](repeating: 5, count: 190)
        result[0] = 2
        return result
    }()

    static func lines(_ text: String, width: Int = 100, height: Int = 40,
                      centered: Bool = false) -> [OriginalBriefingTextLayout.Line] {
        guard let result = OriginalBriefingTextLayout.make(text: text, characterWidths: widths,
            lineHeight: 4, width: width, height: height, centered: centered) else {
            preconditionFailure("Valid synthetic TextWindow input rejected")
        }
        return result
    }

    static func main() {
        let tabs = lines("A\tB ", centered: true)
        precondition(tabs.count == 1 && tabs[0].text == "A\tB ")
        precondition(tabs[0].x == 44 && tabs[0].y == 0 && tabs[0].layout.width == 12)
        precondition(tabs[0].layout.glyphs.map { $0.index } == [33, 34, 0])
        precondition(tabs[0].layout.glyphs.map { $0.x } == [0, 5, 10], "Tabs do not advance a TextWindow pen")

        let exact = lines("AB", width: 10, centered: true)
        precondition(exact.map { $0.text } == ["A", "B"], "Original wrap boundary is >=, not >")
        precondition(exact.map { $0.x } == [2, 2] && exact.map { $0.y } == [0, 4])
        let longWord = lines("AAAA", width: 12)
        precondition(longWord.map { $0.text } == ["AA", "AA"])
        precondition(longWord.map { $0.layout.width } == [10, 10])

        let soft = lines("A A", width: 12, centered: true)
        precondition(soft.map { $0.text } == ["A ", "A"], "Soft-break space remains in the preceding draw range")
        precondition(soft.map { $0.layout.width } == [5, 7], "Preserve source lineWidthList, not recomputed trimmed widths")
        precondition(soft.map { $0.x } == [3, 2])
        precondition(soft[0].layout.glyphs.map { $0.x } == [0, 5])

        let explicitSpaces = lines("A \nB  ", centered: true)
        precondition(explicitSpaces.map { $0.text } == ["A ", "B  "])
        precondition(explicitSpaces.map { $0.layout.width } == [7, 9])
        precondition(explicitSpaces.map { $0.x } == [46, 45], "Final spaces affect centering; integer halves truncate")
        let tail = lines("A\nB\nC", height: 9)
        precondition(tail.map { $0.text } == ["B", "C"] && tail.map { $0.y } == [0, 4],
                     "Show last fitting whole lines at top, not partial lines or the first lines")
        precondition(lines("A", height: 3).isEmpty)
        precondition(lines("A", height: 0).isEmpty)
        precondition(lines("A\n", height: 4).map { $0.text } == [""])
        precondition(lines("").map { $0.text } == [""])
        precondition(lines("A\u{7}Hidden").map { $0.text } == ["A"])

        let oversized = lines("A", width: 4, centered: true)
        precondition(oversized.map { $0.text } == ["", "A"])
        precondition(oversized.map { $0.x } == [2, 0], "Negative half-pixel center truncates toward zero")
        precondition(lines("A", width: 3, centered: true).map { $0.x } == [1, -1])

        let caret = lines("A\u{cb}B")[0].layout
        precondition(caret.width == 10)
        precondition(caret.glyphs.map { $0.index } == [33, 34, 171])
        precondition(caret.glyphs.map { $0.x } == [0, 5, 1], "Caret overlays following glyph after it is drawn")
        let trailingCaret = lines("A\u{cb}")[0].layout
        precondition(trailingCaret.width == 5 && trailingCaret.glyphs.map { $0.x } == [0, 1])
        precondition(lines("\u{cb}\u{cb}A")[0].layout.glyphs.map { $0.index } == [33, 171])

        for input in ["\u{0}", "\r", "\u{1b}", "😀", String(repeating: "A", count: 4097)] {
            precondition(OriginalBriefingTextLayout.make(text: input, characterWidths: widths,
                lineHeight: 4, width: 100, height: 40, centered: false) == nil)
        }
        for badWidths in [[], Array(widths.dropLast()), [Int](repeating: 0, count: 190),
                          [Int](repeating: 4097, count: 190)] {
            precondition(OriginalBriefingTextLayout.make(text: "A", characterWidths: badWidths,
                lineHeight: 4, width: 100, height: 40, centered: false) == nil)
        }
        for (lineHeight, width, height) in [(0, 100, 40), (4097, 100, 40), (4, 0, 40),
                                           (4, 8193, 40), (4, 100, -1), (4, 100, 8193)] {
            precondition(OriginalBriefingTextLayout.make(text: "A", characterWidths: widths,
                lineHeight: lineHeight, width: width, height: height, centered: false) == nil)
        }
        print("Original briefing TextWindow layout tests passed")
    }
}
