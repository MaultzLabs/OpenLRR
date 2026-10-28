import Foundation

/// Original NERPMessageFile text and sound references from user assets.
struct NativeNERPsMessageFile {
    enum MessageError: Error { case oversized }
    let lines: [String]
    private let soundDefinitions: [String: String]
    private let lineSoundKeys: [[String]]

    init(data: Data) throws {
        guard data.count <= 1_000_000 else { throw MessageError.oversized }
        var parsed: [String] = []
        var definitions: [String: String] = [:]
        var keys: [[String]] = []
        var current: [UInt8] = []
        func finishLine() {
            guard !current.isEmpty else { return }
            let text = String(data: Data(current), encoding: .windowsCP1252)
                ?? String(decoding: current, as: UTF8.self)
            if text.hasPrefix("$") {
                let parts = text.dropFirst().split(whereSeparator: { $0.isWhitespace })
                if parts.count == 2 {
                    let key = String(parts[0]).lowercased()
                    let path = String(parts[1]).replacingOccurrences(of: "\\", with: "/")
                    let components = path.split(separator: "/", omittingEmptySubsequences: false)
                    if !components.isEmpty, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }) {
                        definitions[key] = path.lowercased().hasSuffix(".wav") ? path : path + ".wav"
                    }
                }
            } else if !text.hasPrefix(":") {
                parsed.append(Self.visibleText(text).replacingOccurrences(of: "_", with: " "))
                var references: [String] = []
                var cursor = text.startIndex
                while let start = text[cursor...].firstIndex(of: "#") {
                    let after = text.index(after: start)
                    guard let end = text[after...].firstIndex(of: "#") else { break }
                    references.append(String(text[after..<end]).lowercased())
                    cursor = text.index(after: end)
                }
                keys.append(references)
            }
            current.removeAll(keepingCapacity: true)
        }
        // NERPsFile_LoadMessageFile replaces underscores and splits on any
        // control character, not only CR/LF.
        for byte in data {
            // Tabs separate a definition key from its path; preserve them.
            if byte < 0x20 && !(byte == 9 && (current.first == 0x24 || current.first == 0x3a)) { finishLine() }
            else { current.append(byte) }
        }
        finishLine()
        lines = parsed
        soundDefinitions = definitions
        lineSoundKeys = keys
    }

    /// SetMessage uses one-based lines; zero also selects the first line.
    func text(for number: Int32) -> String? {
        guard number >= 0 else { return nil }
        let index = number == 0 ? 0 : Int(number) - 1
        return lines.indices.contains(index) ? lines[index] : nil
    }

    func soundPaths(for number: Int32) -> [String] {
        guard number >= 0 else { return [] }
        let index = number == 0 ? 0 : Int(number) - 1
        guard lineSoundKeys.indices.contains(index) else { return [] }
        return lineSoundKeys[index].compactMap { soundDefinitions[$0] }
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
