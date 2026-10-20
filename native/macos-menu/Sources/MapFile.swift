import Foundation

/// Original binary MAP file format: 'MAP ' + payload byte length + width +
/// height + width*height little-endian UInt16 entries. Format applies to
/// terrain, predug, height, erosion and other original level maps.
struct RockRaidersMap {
    enum MapError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let message): return "Invalid Rock Raiders MAP: \(message)" }
        }
    }

    let width: Int
    let height: Int
    private let cells: [UInt16]

    init(data: Data) throws {
        guard data.count >= 16, data.count <= 32_000_000,
              data.prefix(4) == Data([77, 65, 80, 32]) else {
            throw MapError.invalid("missing MAP header or unreasonable file size")
        }
        func le32(_ offset: Int) -> UInt32 {
            UInt32(data[offset]) | (UInt32(data[offset+1]) << 8) |
            (UInt32(data[offset+2]) << 16) | (UInt32(data[offset+3]) << 24)
        }
        let declared = Int(le32(4))
        let width = Int(le32(8))
        let height = Int(le32(12))
        guard (1...4096).contains(width), (1...4096).contains(height),
              width <= 16_000_000 / height else {
            throw MapError.invalid("invalid map dimensions")
        }
        let expected = 8 + 2 * width * height
        guard declared == expected, declared == data.count - 8 else {
            throw MapError.invalid("payload size disagrees with dimensions")
        }
        var values = [UInt16]()
        values.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            let at = 16 + index * 2
            values.append(UInt16(data[at]) | (UInt16(data[at+1]) << 8))
        }
        self.width = width
        self.height = height
        self.cells = values
    }

    func value(x: Int, y: Int) -> UInt16? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        return cells[y * width + x]
    }

    var cellCount: Int { cells.count }
}
