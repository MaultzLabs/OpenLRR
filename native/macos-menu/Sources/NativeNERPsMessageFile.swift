import Foundation

/// Text-only reader for original NERPMessageFile lines. Bitmap/sound
/// definitions are not copied or played; all text comes from user assets.
struct NativeNERPsMessageFile {
    enum MessageError: Error { case oversized }
    let lines: [String]

    init(data: Data) throws {
        guard data.count <= 1_000_000 else { throw MessageError.oversized }
        var parsed: [String] = []
        var current: [UInt8] = []
        func finishLine() {
            guard !current.isEmpty else { return }
            let text = String(data: Data(current), encoding: .windowsCP1252)
                ?? String(decoding: current, as: UTF8.self)
            if !text.hasPrefix(":") && !text.hasPrefix("$") {
                parsed.append(Self.visibleText(text))
            }
            current.removeAll(keepingCapacity: true)
        }
        // NERPsFile_LoadMessageFile replaces underscores and splits on any
        // control character, not only CR/LF.
        for byte in data {
            if byte < 0x20 { finishLine() }
            else { current.append(byte == 0x5f ? 0x20 : byte) }
        }
        finishLine()
        lines = parsed
    }

    /// SetMessage uses one-based lines; zero also selects the first line.
    func text(for number: Int32) -> String? {
        guard number >= 0 else { return nil }
        let index = number == 0 ? 0 : Int(number) - 1
        return lines.indices.contains(index) ? lines[index] : nil
    }

    private static func visibleText(_ source: String) -> String {
        // Omit inline <image> and #sound# tokens in this text-only preview.
        var result = ""
        var cursor = source.startIndex
        while cursor < source.endIndex {
            let symbol = source[cursor]
            if symbol == "<" || symbol == "#" {
                let close: Character = symbol == "<" ? ">" : "#"
                let after = source.index(after: cursor)
                if let end = source[after...].firstIndex(of: close) {
                    cursor = source.index(after: end)
                    continue
                }
            }
            result.append(symbol)
            cursor = source.index(after: cursor)
        }
        return result
    }
}
