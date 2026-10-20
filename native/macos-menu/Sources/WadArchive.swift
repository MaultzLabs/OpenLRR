import Foundation

/// Read-only parser for classic Rock Raiders WWAD containers.
/// Portable Foundation-only core; no Wine or game EXE is required.
struct WadArchive {
    enum WadError: Error, CustomStringConvertible {
        case invalid(String)
        case notFound(String)
        case unsupportedCompression(String)

        var description: String {
            switch self {
            case .invalid(let message): return "Invalid WWAD: \(message)"
            case .notFound(let name): return "Asset not found in WWAD: \(name)"
            case .unsupportedCompression(let name): return "RNC-compressed asset not yet supported: \(name)"
            }
        }
    }

    struct Entry {
        let path: String
        let flags: UInt32
        let packedSize: Int
        let unpackedSize: Int
        let offset: Int
    }

    let entries: [Entry]
    private let bytes: Data
    private let paths: [String: Int]

    init(url: URL) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        try self.init(data: data)
    }

    init(data: Data) throws {
        guard data.count >= 8, data.prefix(4) == Data([87, 87, 65, 68]) else {
            throw WadError.invalid("missing WWAD signature")
        }
        func number(_ offset: Int) throws -> UInt32 {
            guard offset >= 0, offset <= data.count - 4 else {
                throw WadError.invalid("truncated 32-bit field")
            }
            return UInt32(data[offset]) | (UInt32(data[offset+1]) << 8) |
                (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
        }
        let count = Int(try number(4))
        guard count >= 0, count <= 100_000, count <= data.count / 18 else {
            throw WadError.invalid("unreasonable file count")
        }
        var cursor = 8
        func cstring() throws -> String {
            guard cursor < data.count else { throw WadError.invalid("missing filename") }
            let limit = min(data.count, cursor + 8193)
            var end = cursor
            while end < limit && data[end] != 0 { end += 1 }
            guard end < limit && end < data.count else {
                throw WadError.invalid("filename exceeds 8192 bytes or is unterminated")
            }
            let raw = data.subdata(in: cursor..<end)
            guard let value = String(data: raw, encoding: .utf8) ??
                              String(data: raw, encoding: .isoLatin1), !value.isEmpty else {
                throw WadError.invalid("filename is empty or invalid")
            }
            cursor = end + 1
            return value
        }
        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0..<count { names.append(try cstring()) }
        for _ in 0..<count { _ = try cstring() }
        guard cursor <= data.count, count <= (data.count - cursor) / 16 else {
            throw WadError.invalid("truncated entry table")
        }
        let firstPayload = cursor + count * 16
        var records: [Entry] = []
        var dictionary: [String: Int] = [:]
        records.reserveCapacity(count)
        for i in 0..<count {
            let at = cursor + i * 16
            let flags = try number(at)
            let packed = Int(try number(at + 4))
            let unpacked = Int(try number(at + 8))
            let offset = Int(try number(at + 12))
            guard offset >= firstPayload, offset <= data.count,
                  packed <= data.count - offset else {
                throw WadError.invalid("asset \(i) points outside the archive")
            }
            if flags & 2 == 0 && packed != unpacked {
                throw WadError.invalid("stored asset \(i) has inconsistent lengths")
            }
            let record = Entry(path: names[i], flags: flags, packedSize: packed,
                               unpackedSize: unpacked, offset: offset)
            records.append(record)
            dictionary[Self.normalized(names[i])] = i
        }
        self.entries = records
        self.bytes = data
        self.paths = dictionary
    }

    static func normalized(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    func contains(_ path: String) -> Bool { paths[Self.normalized(path)] != nil }

    func asset(_ path: String, maximumBytes: Int = 50_000_000) throws -> Data {
        guard let i = paths[Self.normalized(path)] else { throw WadError.notFound(path) }
        let entry = entries[i]
        guard entry.flags & 2 == 0 else { throw WadError.unsupportedCompression(entry.path) }
        guard entry.packedSize <= maximumBytes else {
            throw WadError.invalid("asset exceeds read limit")
        }
        return bytes.subdata(in: entry.offset..<(entry.offset + entry.packedSize))
    }
}
