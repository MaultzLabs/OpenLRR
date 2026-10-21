import Foundation

/// Original 8-bit Windows BMP loader for the menu's indexed sprite-font art.
/// Pen/index zero becomes transparent. Pen 255 marks trailing glyph-cell space
/// on the top scanline (matching Gods98::Font_Load in OpenLRR).
struct PalettedBMP {
    enum DecodeError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let message): return "Unsupported original BMP: \(message)" }
        }
    }

    let width: Int
    let height: Int
    let rgba: [UInt8] // Top-to-bottom RGBA, alpha 0 for palette index 0.
    private let indices: [UInt8]

    init(data: Data) throws {
        guard data.count >= 54, data.count <= 50_000_000,
              data[0] == 66 && data[1] == 77 else {
            throw DecodeError.invalid("missing BMP header or oversized image")
        }
        func word(_ pos: Int) -> UInt16 {
            UInt16(data[pos]) | (UInt16(data[pos + 1]) << 8)
        }
        func dword(_ pos: Int) -> UInt32 {
            UInt32(data[pos]) | (UInt32(data[pos + 1]) << 8) |
            (UInt32(data[pos + 2]) << 16) | (UInt32(data[pos + 3]) << 24)
        }
        let start = Int(dword(10)), headerSize = Int(dword(14))
        guard headerSize >= 40, headerSize <= 124,
              14 + headerSize <= data.count else {
            throw DecodeError.invalid("unsupported DIB header")
        }
        let signedWidth = Int32(bitPattern: dword(18))
        let signedHeight = Int32(bitPattern: dword(22))
        guard signedWidth > 0, signedWidth <= 8192,
              signedHeight != 0, signedHeight != Int32.min,
              abs(signedHeight) <= 8192,
              word(26) == 1, word(28) == 8, dword(30) == 0 else {
            throw DecodeError.invalid("requires uncompressed 8-bit indexed pixels")
        }
        let width = Int(signedWidth)
        let height = Int(abs(signedHeight))
        guard width <= 16_000_000 / height else {
            throw DecodeError.invalid("image dimensions exceed decoded pixel budget")
        }
        let paletteStart = 14 + headerSize
        let declaredCount = Int(dword(46))
        let colorCount = declaredCount == 0 ? 256 : declaredCount
        guard (1...256).contains(colorCount), paletteStart + colorCount * 4 <= start,
              start <= data.count else {
            throw DecodeError.invalid("palette missing or overlaps pixels")
        }
        let pitch = (width + 3) & ~3
        guard pitch <= (data.count - start) / height else {
            throw DecodeError.invalid("truncated image pixels")
        }
        var indexData = [UInt8](repeating: 0, count: width * height)
        var colors = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let diskRow = signedHeight > 0 ? height - 1 - y : y
            for x in 0..<width {
                let idx = Int(data[start + diskRow * pitch + x])
                guard idx < colorCount else {
                    throw DecodeError.invalid("pixel palette index out of bounds")
                }
                indexData[y * width + x] = UInt8(idx)
                let palettePosition = paletteStart + idx * 4
                let at = (y * width + x) * 4
                colors[at] = data[palettePosition + 2]     // red
                colors[at + 1] = data[palettePosition + 1] // green
                colors[at + 2] = data[palettePosition]     // blue
                colors[at + 3] = idx == 0 ? 0 : 255
            }
        }
        self.width = width
        self.height = height
        self.indices = indexData
        self.rgba = colors
    }

    /// Pointer_Load calls Image_SetupTrans with RGB(0,0,0), unlike the
    /// bitmap-font renderer, which uses palette index zero as its mask.
    /// Preserve every nonblack palette entry, including a nonblack index 0.
    /// Return a separate buffer so the font atlas retains its original mask.
    func blackKeyedRGBA() -> [UInt8] {
        var keyed = rgba
        for position in stride(from: 0, to: keyed.count, by: 4) {
            keyed[position + 3] = keyed[position] == 0 &&
                keyed[position + 1] == 0 && keyed[position + 2] == 0 ? 0 : 255
        }
        return keyed
    }

    func index(x: Int, y: Int) -> UInt8? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        return indices[y * width + x]
    }

    /// 10 columns * 19 rows, printable 8-bit characters starting at ASCII 32.
    func originalFontWidths() throws -> [Int] {
        guard width % 10 == 0, height % 19 == 0,
              width >= 10, height >= 19 else {
            throw DecodeError.invalid("font atlas is not a 10x19 grid")
        }
        let cellWidth = width / 10
        let cellHeight = height / 19
        var result: [Int] = []
        result.reserveCapacity(190)
        for row in 0..<19 {
            for column in 0..<10 {
                var length = cellWidth
                // The game inspects the right end of the TOP row for pen 255.
                while length > 1 {
                    let x = column * cellWidth + length - 1
                    if index(x:x,y:row * cellHeight) == 255 { length -= 1 }
                    else { break }
                }
                result.append(length)
            }
        }
        return result
    }
}
