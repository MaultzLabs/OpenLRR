#if os(macOS)
import AppKit
struct OriginalBitmapFont {
    let image: NSImage
    let characterWidths: [Int]
    let cellWidth: Int
    let cellHeight: Int
    let sheetHeight: Int

    func layout(_ text: String) -> OriginalFontLayout? {
        OriginalFontLayout.make(text, characterWidths: characterWidths,
                                lineHeight: cellHeight)
    }

    func draw(_ layout: OriginalFontLayout, at point: CGPoint) {
        for placement in layout.glyphs {
            let col = placement.index % 10
            let row = placement.index / 10
            let width = CGFloat(characterWidths[placement.index])
            let source = CGRect(x: CGFloat(col * cellWidth),
                                y: CGFloat(sheetHeight - ((row + 1) * cellHeight)),
                                width: width, height: CGFloat(cellHeight))
            let destination = CGRect(x: point.x + CGFloat(placement.x),
                                     y: point.y + CGFloat(placement.y),
                                     width: width, height: CGFloat(cellHeight))
            image.draw(in: destination, from: source, operation: .sourceOver,
                       fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    static func load(_ path: String, resources: GameResources) -> Self? {
        guard let bytes = try? resources.data(at: path, maximumBytes: 15_000_000),
              let bitmap = try? PalettedBMP(data: bytes),
              let widths = try? bitmap.originalFontWidths(),
              let source = CGDataProvider(data: Data(bitmap.rgba) as CFData),
              let cg = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: source, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return Self(image: NSImage(cgImage: cg, size: CGSize(width: bitmap.width, height: bitmap.height)),
                    characterWidths: widths, cellWidth: bitmap.width / 10,
                    cellHeight: bitmap.height / 19, sheetHeight: bitmap.height)
    }
}
#endif
