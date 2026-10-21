import Foundation

/// Safe subset of the original Lego.cfg grammar: semicolon comments, brace
/// sections, and single-line key/value settings (including ':'-delimited menus).
/// This retains asset names and coordinates rather than fabricating menu data.
struct LegoConfig {
    enum ConfigError: Error, CustomStringConvertible {
        case malformed(String)
        var description: String {
            switch self { case .malformed(let value): return "Malformed Lego.cfg: \(value)" }
        }
    }

    private let properties: [String: String]
    private let sectionPaths: [[String]]

    init(data: Data) throws {
        guard data.count <= 10_000_000 else { throw ConfigError.malformed("file too large") }
        guard let content = String(data: data, encoding: .utf8) ??
                            String(data: data, encoding: .isoLatin1) else {
            throw ConfigError.malformed("cannot decode text")
        }
        try self.init(text: content)
    }

    init(text: String) throws {
        guard text.utf8.count <= 10_000_000 else { throw ConfigError.malformed("file too large") }
        var values: [String: String] = [:]
        var section: [String] = []
        var visitedSections: [[String]] = []
        var pending: String?
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var buffer = ""
        var comment = false
        var line = 1

        func record(_ text: String) {
            let elements = text.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard elements.count == 2 else { return }
            let name = String(elements[0]).lowercased()
            let value = String(elements[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = (section + [name]).joined(separator: "::").lowercased()
            // Vanilla CFG paths are case-insensitive; preserve first declaration.
            if values[key] == nil { values[key] = value }
        }

        for char in normalized + "\n" {
            if char == "\n" {
                let trimmed = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    if trimmed.split(whereSeparator: { $0.isWhitespace }).count == 1 {
                        pending = trimmed
                    } else {
                        record(trimmed)
                        pending = nil
                    }
                }
                buffer = ""
                comment = false
                line += 1
                continue
            }
            if comment { continue }
            if char == ";" { comment = true; continue }
            if char == "{" {
                let label = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                buffer = ""
                let selected = label.isEmpty ? pending : label
                guard let name = selected, !name.isEmpty,
                      name.split(whereSeparator: { $0.isWhitespace }).count == 1,
                      section.count < 64 else {
                    throw ConfigError.malformed("invalid section opening at line \(line)")
                }
                section.append(name)
                visitedSections.append(section)
                pending = nil
            } else if char == "}" {
                let tail = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tail.isEmpty { record(tail) }
                buffer = ""
                guard !section.isEmpty else {
                    throw ConfigError.malformed("unexpected closing brace at line \(line)")
                }
                section.removeLast()
                pending = nil
            } else {
                buffer.append(char)
                if buffer.utf8.count > 8192 {
                    throw ConfigError.malformed("line exceeds 8192 bytes at line \(line)")
                }
            }
        }
        guard section.isEmpty else { throw ConfigError.malformed("unclosed configuration section") }
        guard !values.isEmpty else { throw ConfigError.malformed("no usable settings") }
        properties = values
        sectionPaths = visitedSections
    }

    /// The retail game uses Lego* as the top section, but alternate game-name
    /// section prefixes can be read if explicitly supplied.
    func value(_ sections: String...) -> String? {
        properties[sections.joined(separator: "::").lowercased()]
    }

    func value(path: [String]) -> String? {
        properties[path.joined(separator: "::").lowercased()]
    }

    func valueUnderGame(_ parts: [String]) -> String? {
        for prefix in ["Lego*", "Lego", "LegoRR"] {
            if let setting = value(path: [prefix] + parts) { return setting }
        }
        return nil
    }

    /// Directly nested original CFG sections, in source order. Required for
    /// .ol object lists, whose Object1/Object2 keys are section names rather
    /// than settings. No object IDs are invented from missing declarations.
    func childSections(under path: [String]) -> [String] {
        var seen = Set<String>()
        return sectionPaths.compactMap { section in
            guard section.count == path.count + 1,
                  zip(section.prefix(path.count), path).allSatisfy({
                      $0.0.caseInsensitiveCompare($0.1) == .orderedSame
                  }) else { return nil }
            let name = section[section.count - 1]
            guard seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    var settingCount: Int { properties.count }
}
