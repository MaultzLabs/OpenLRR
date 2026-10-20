#if os(macOS)
import AppKit
import Foundation
import ImageIO

/// Prototype view: places real WAD images and Lego.cfg menu items at the
/// original logical 640x480 coordinates. Font and overlays remain incomplete.
private struct OriginalBitmapFont {
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
}

final class OriginalMenuCanvas: NSView {
    var resources: GameResources? { didSet { clearCache(); needsDisplay = true } }
    var definitions: MenuDefinition? { didSet { menuIndex = 0; needsDisplay = true } }
    var onNavigation: ((String) -> Void)?
    private var menuIndex = 0
    private var hoverIndex: Int?
    private var imageCache: [String: NSImage] = [:]
    private var fontCache: [String: OriginalBitmapFont] = [:]
    private var missingFonts = Set<String>()
    private var unavailable = Set<String>()
    private var hitRects: [(Int, CGRect)] = []
    private var history: [Int] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func clearCache() {
        imageCache.removeAll()
        fontCache.removeAll()
        missingFonts.removeAll()
        unavailable.removeAll()
        history.removeAll()
        hoverIndex = nil
        hitRects.removeAll()
    }

    /// AppKit's ImageIO decodes the actual BMP bytes from the archive, without
    /// converting or saving copyrighted images to public or temporary files.
    private func image(_ originalPath: String) -> NSImage? {
        let path = originalPath.split(separator: ":", omittingEmptySubsequences: false)
                               .first.map(String.init) ?? originalPath
        let key = WadArchive.normalized(path)
        if let cached = imageCache[key] { return cached }
        if unavailable.contains(key) { return nil }
        do {
            guard let bytes = try resources?.data(at: path, maximumBytes: 40_000_000),
                  bytes.count >= 2,
                  bytes.prefix(2) == Data([66, 77]),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  image.width > 0, image.height > 0,
                  image.width <= 8192, image.height <= 8192 else {
                unavailable.insert(key)
                return nil
            }
            let result = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            imageCache[key] = result
            return result
        } catch {
            unavailable.insert(key)
            return nil
        }
    }

    private func originalFont(_ path: String?) -> OriginalBitmapFont? {
        guard let path, !path.isEmpty else { return nil }
        let key = WadArchive.normalized(path)
        if let cached = fontCache[key] { return cached }
        if missingFonts.contains(key) { return nil }
        do {
            guard let bytes = try resources?.data(at: path, maximumBytes: 15_000_000) else {
                missingFonts.insert(key)
                return nil
            }
            let bitmap = try PalettedBMP(data: bytes)
            let widths = try bitmap.originalFontWidths()
            guard let dataSource = CGDataProvider(data: Data(bitmap.rgba) as CFData),
                  let cg = CGImage(width: bitmap.width, height: bitmap.height,
                                   bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: bitmap.width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: dataSource, decode: nil,
                                   shouldInterpolate: false, intent: .defaultIntent) else {
                missingFonts.insert(key)
                return nil
            }
            let atlas = OriginalBitmapFont(
                image: NSImage(cgImage: cg, size: CGSize(width: bitmap.width, height: bitmap.height)),
                characterWidths: widths, cellWidth: bitmap.width / 10,
                cellHeight: bitmap.height / 19, sheetHeight: bitmap.height)
            fontCache[key] = atlas
            return atlas
        } catch {
            missingFonts.insert(key)
            return nil
        }
    }

    private func imageFrame(for raw: String, fallback: CGRect) -> CGRect {
        // Original Front_Menu_LoadMenuImage uses path[:x:y[:transparent]].
        let fields = raw.split(separator: ":", omittingEmptySubsequences: false)
        if fields.count >= 3, let x = Double(fields[1]), let y = Double(fields[2]),
           let art = image(String(fields[0])) {
            return CGRect(x: x, y: y, width: art.size.width, height: art.size.height)
        }
        return fallback
    }

    private func drawImage(_ bitmap: NSImage, at rectangle: CGRect) {
        bitmap.draw(in: rectangle, from: .zero, operation: .sourceOver,
                    fraction: 1, respectFlipped: true, hints: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSRectFill(bounds)
        guard resources != nil, let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        ctx.cgContext.scaleBy(x: bounds.width / 640.0, y: bounds.height / 480.0)
        hitRects.removeAll()

        let backgroundName = "Interface/FrontEnd/MenuBGpic.bmp"
        if let background = image(backgroundName) {
            drawImage(background, at: CGRect(x: 0, y: 0, width: 640, height: 480))
        }
        guard let definitions, definitions.menus.indices.contains(menuIndex) else { return }
        let menu = definitions.menus[menuIndex]
        if let source = menu.backgroundImage, let img = image(source) {
            drawImage(img, at: imageFrame(for: source,
                                          fallback: CGRect(x: 0, y: 0, width: 640, height: 480)))
        }
        // Show only known BMP overlays. Original FLIC/AVI/LWS animations must be
        // handled by dedicated decoders, not by inventing placeholder animations.
        for overlay in menu.overlays where overlay.asset.lowercased().hasSuffix(".bmp") {
            if let art = image(overlay.asset) {
                drawImage(art, at: CGRect(x: overlay.x, y: overlay.y,
                                          width: art.size.width, height: art.size.height))
            }
        }

        let title = menu.internalName.isEmpty ? menu.title : menu.internalName
        if !title.isEmpty {
            drawText(title, x: 320, y: 18, size: 23, hovered: false, enabled: false,
                     centered: true, fontPath: menu.titleFont)
        }

        for (i, item) in menu.items.enumerated() {
            let x = CGFloat(menu.x + item.x)
            let y = CGFloat(menu.y + item.y)
            let hovered = hoverIndex == i
            let actionable = item.kind == .next && item.linkedMenu != nil
            let assetPath = hovered ? (item.imageHover ?? item.imageNormal) : item.imageNormal
            if let assetPath, let artwork = image(assetPath) {
                let rect = CGRect(x: x, y: y, width: artwork.size.width,
                                  height: artwork.size.height)
                drawImage(artwork, at: rect)
                if actionable { hitRects.append((i, rect)) }
            } else if !item.caption.isEmpty {
                let measured = drawText(item.caption, x: x, y: y, size: 22,
                                        hovered: hovered, enabled: actionable, centered: false,
                                        fontPath: hovered ? menu.hoverFont : menu.normalFont)
                if actionable { hitRects.append((i, measured)) }
            }
        }
    }

    @discardableResult private func drawText(_ content: String, x: CGFloat, y: CGFloat,
                                              size: CGFloat, hovered: Bool,
                                              enabled: Bool, centered: Bool,
                                              fontPath: String?) -> CGRect {
        if let atlas = originalFont(fontPath), let layout = atlas.layout(content) {
            let width = CGFloat(layout.width)
            let x = centered ? x - width / 2 : x
            atlas.draw(layout, at: CGPoint(x: x, y: y))
            return CGRect(x: x, y: y, width: width,
                          height: CGFloat(layout.height)).insetBy(dx: -3, dy: -3)
        }
        // System font is only a fallback when the specific original font BMP
        // is not present/decodable. Never ship replacement font image assets.
        let font = NSFont.boldSystemFont(ofSize: size)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: enabled ? (hovered ? NSColor.white : NSColor.yellow) : NSColor.lightGray
        ]
        let sz = (content as NSString).size(withAttributes: attributes)
        let actualX = centered ? x - sz.width / 2 : x
        let rect = CGRect(x: actualX, y: y, width: sz.width, height: sz.height)
        (content as NSString).draw(at: rect.origin, withAttributes: attributes)
        return rect.insetBy(dx: -3, dy: -3)
    }

    override func updateTrackingAreas() {
        for tracking in trackingAreas { removeTrackingArea(tracking) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func logicalPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * 640.0 / bounds.width, y: p.y * 480.0 / bounds.height)
    }

    override func mouseMoved(with event: NSEvent) {
        let pos = logicalPoint(event)
        let newHover = hitRects.first(where: { $0.1.contains(pos) })?.0
        if hoverIndex != newHover { hoverIndex = newHover; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let pos = logicalPoint(event)
        guard let index = hitRects.first(where: { $0.1.contains(pos) })?.0,
              let menus = definitions?.menus, menus.indices.contains(menuIndex),
              menus[menuIndex].items.indices.contains(index) else { return }
        let selected = menus[menuIndex].items[index]
        if selected.kind == .next, let next = selected.linkedMenu,
           menus.indices.contains(next) {
            history.append(menuIndex)
            menuIndex = next
            hoverIndex = nil
            needsDisplay = true
            onNavigation?("Original menu: \(menus[next].internalName)")
        }
        // Trigger / Select / Slider operations are deliberately not emulated;
        // displaying menus never launches or modifies the user's game.
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, let previous = history.popLast() {
            menuIndex = previous
            hoverIndex = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }
}

/// Creates a real native ARM64 AppKit window and reads only the selected WADs.
final class NativeMenuApplication: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var canvas: OriginalMenuCanvas!
    private var status: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rock Raiders — Native Mac Prototype"
        window.center()
        window.minSize = NSSize(width: 640, height: 480)
        window.contentAspectRatio = NSSize(width: 4, height: 3)
        let root = NSView(frame: window.contentView!.bounds)
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = root

        canvas = OriginalMenuCanvas(frame: root.bounds)
        canvas.autoresizingMask = [.width, .height]
        canvas.onNavigation = { [weak self] value in self?.status.stringValue = value }
        root.addSubview(canvas)

        let toolbar = NSVisualEffectView(frame: CGRect(x: 0, y: 520, width: 800, height: 80))
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.autoresizingMask = [.width, .minYMargin]
        root.addSubview(toolbar)

        let open = NSButton(title: "Open original WAD files…", target: self,
                            action: #selector(openArchive))
        let about = NSButton(title: "About", target: self, action: #selector(aboutPrototype))
        let quit = NSButton(title: "Quit", target: NSApp,
                            action: #selector(NSApplication.terminate(_:)))
        let buttons = NSStackView(views: [open, about, quit])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 12
        buttons.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(buttons)

        status = NSTextField(labelWithString: "Select LegoRR0.wad; adjacent LegoRR1.wad will be read if present.")
        status.lineBreakMode = .byTruncatingTail
        status.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(status)
        NSLayoutConstraint.activate([
            buttons.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            buttons.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 9),
            status.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 7)
        ])
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.count > 1 {
            load(URL(fileURLWithPath: CommandLine.arguments[1]))
        }
    }

    @objc private func openArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose your own LegoRR0.wad or LegoRR1.wad. Nothing is copied or uploaded."
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK, let url = panel.url { self?.load(url) }
        }
    }

    private func load(_ url: URL) {
        do {
            let resources = try GameResources(selectedWadURL: url)
            guard resources.exists("Interface/FrontEnd/MenuBGpic.bmp") else {
                throw GameResources.ResourceError.missingAsset("Interface/FrontEnd/MenuBGpic.bmp")
            }
            canvas.resources = resources
            if resources.exists("Lego.cfg") {
                let config = try LegoConfig(data: resources.configData())
                canvas.definitions = try MenuDefinition(config: config)
                status.stringValue = "Original WADs and \(canvas.definitions?.menus.count ?? 0) configured menus loaded. Actions incomplete."
            } else {
                canvas.definitions = nil
                status.stringValue = "Original background loaded. LegoRR1.wad with Lego.cfg is needed for navigation."
            }
            window.title = "Rock Raiders — Original Asset Native Prototype"
        } catch {
            status.stringValue = "Game resources could not be loaded."
            let alert = NSAlert()
            alert.messageText = "Cannot load the original Rock Raiders resources"
            alert.informativeText = "\(error)\nNo game files were modified."
            alert.alertStyle = .warning
            alert.beginSheetModal(for: window)
        }
    }

    @objc private func aboutPrototype() {
        let alert = NSAlert()
        alert.messageText = "Original assets, native macOS prototype"
        alert.informativeText = "Reads the original WAD archives and Lego.cfg to draw the menu background and navigate configured Next links. Bitmap fonts, animations, audio, game logic and missions are not ported. This viewer never launches the Windows game or modifies the original files."
        alert.beginSheetModal(for: window)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main struct NativeMenuMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let delegate = NativeMenuApplication()
        app.delegate = delegate
        app.run()
    }
}
#endif
