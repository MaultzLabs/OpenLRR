#if os(macOS)
import AppKit
import ImageIO

/// Reconstructs the retail cursor *from the user's original Pointer_Standard
/// bitmap*, including black-as-transparent pixels as configured by
/// Pointers.cpp::Pointer_Load and Image_SetupTrans(black).
enum OriginalMacCursor {
    static func load(config: LegoConfig, resources: GameResources) -> NSCursor? {
        guard let path = OriginalPointerAsset.standardPath(
            config: config, resources: resources),
              let data = try? resources.data(at: path, maximumBytes: 2_000_000) else {
            return nil
        }

        if let bitmap = try? PalettedBMP(data: data),
           bitmap.width <= 128, bitmap.height <= 128,
           let cg = imageFromRGBA(bitmap.rgba, width: bitmap.width,
                                  height: bitmap.height) {
            return NSCursor(image: NSImage(cgImage: cg,
                               size: NSSize(width: bitmap.width, height: bitmap.height)),
                            hotSpot: .zero)
        }

        // Some original cursor BMPs are non-indexed. ImageIO can decode them;
        // remove the retail transparent-key color (black) on a bounded bitmap.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              (1...128).contains(original.width),
              (1...128).contains(original.height) else { return nil }

        let width = original.width, height = original.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = rgba.withUnsafeMutableBytes { buffer -> Bool in
            let info = CGBitmapInfo.byteOrder32Big.rawValue |
                       CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data: buffer.baseAddress,
                                          width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: info) else { return false }
            context.draw(original, in: CGRect(x: 0, y: 0,
                                              width: width, height: height))
            return true
        }
        guard didDraw else { return nil }
        for at in stride(from: 0, to: rgba.count, by: 4) {
            if rgba[at] == 0 && rgba[at + 1] == 0 && rgba[at + 2] == 0 {
                rgba[at + 3] = 0
            }
        }
        guard let image = imageFromRGBA(rgba, width: width, height: height) else {
            return nil
        }
        return NSCursor(image: NSImage(cgImage: image,
                                      size: NSSize(width: width, height: height)),
                        hotSpot: .zero)
    }

    private static func imageFromRGBA(_ pixels: [UInt8],
                                       width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }
        let info = CGBitmapInfo.byteOrder32Big.rawValue |
                   CGImageAlphaInfo.premultipliedLast.rawValue
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: info),
                       provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }
}
#endif
