import Foundation

/// Main::NextButton* and Panels640x480 are read from the user's CFG.
/// Missing or malformed coordinates do not silently fabricate an asset location.
struct OriginalMissionMessageDefinition {
    let panelPath: String?
    let nextPath: String?
    let nextPosition: CGPoint?

    init(config: LegoConfig?) {
        panelPath = config?.valueUnderGame(["Panels640x480", "Panel_Messages"])?
            .split(separator: ",", omittingEmptySubsequences: false).first.map(String.init)
        nextPath = config?.valueUnderGame(["Main", "NextButton640x480"])
        nextPosition = config?.valueUnderGame(["Main", "NextButtonPos640x480"])
            .flatMap(Self.point)
    }

    /// Extract a literal bitmap reference, without inventing a filename or
    /// treating tooltip/sound fields as resources. Format variants may use
    /// colon or comma separators. Missing images keep the native text control.
    static func firstBitmapPath(_ setting: String?) -> String? {
        setting?.split(whereSeparator: { $0 == ":" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.lowercased().hasSuffix(".bmp") }
    }

    static func point(_ value: String) -> CGPoint? {
        let fields = value.split(separator: ",", omittingEmptySubsequences: false)
        guard fields.count == 2,
              let x = Double(fields[0].trimmingCharacters(in: .whitespaces)),
              let y = Double(fields[1].trimmingCharacters(in: .whitespaces)),
              x.isFinite, y.isFinite, abs(x) <= 8192, abs(y) <= 8192 else { return nil }
        return CGPoint(x: x, y: y)
    }
}

#if os(macOS)
import AppKit

/// Nonmodal mission message overlay. Transparent cave pixels pass input through;
/// the message and its controls consume both mouse buttons, preventing excavation
/// behind the HUD. Text bounds remain provisional pending retail visual review.
final class OriginalMissionMessageUI: NSView {
    private let definition: OriginalMissionMessageDefinition
    private let panel: NSImage?
    private let nextArt: NSImage?
    private let textScroll = NSScrollView()
    private let textView = NSTextView()
    private let nextButton = NSButton(title: "Next ▶", target: nil, action: nil)
    private var logicalScale: CGFloat = 1
    private var logicalOrigin = CGPoint.zero
    var onAdvance: (() -> Void)?
    var originalCursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    override var isFlipped: Bool { true }

    init(resources: GameResources, config: LegoConfig?) {
        definition = OriginalMissionMessageDefinition(config: config)
        panel = Self.image(definition.panelPath, resources: resources)
        nextArt = Self.image(definition.nextPath, resources: resources)
        super.init(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.textColor = .white
        textView.font = .systemFont(ofSize: 12)
        textView.textContainerInset = NSSize(width: 3, height: 2)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textScroll.drawsBackground = false
        textScroll.hasVerticalScroller = true
        textScroll.documentView = textView
        addSubview(textScroll)
        if let nextArt, definition.nextPosition != nil {
            nextButton.image = nextArt
            nextButton.title = ""
            nextButton.isBordered = false
            nextButton.imageScaling = .scaleProportionallyUpOrDown
        }
        nextButton.toolTip = "Continue Chief's message"
        nextButton.setAccessibilityLabel("Continue message")
        nextButton.target = self
        nextButton.action = #selector(advance)
        addSubview(nextButton)
        isHidden = true
    }
    required init?(coder: NSCoder) { nil }

    func update(text: String?, canAdvance: Bool, hideArrow: Bool) {
        let value = text ?? ""
        if textView.string != value {
            textView.string = value
            textView.scrollToBeginningOfDocument(nil)
        }
        isHidden = value.isEmpty
        nextButton.isHidden = hideArrow
        nextButton.isEnabled = canAdvance
        needsDisplay = true
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: originalCursor ?? .arrow) }
    @objc private func advance() {
        guard !isHidden, !nextButton.isHidden, nextButton.isEnabled else { return }
        onAdvance?()
    }

    override func layout() {
        super.layout()
        logicalScale = min(bounds.width / 640, bounds.height / 480)
        logicalOrigin = CGPoint(x: (bounds.width - 640 * logicalScale) / 2,
                                y: bounds.height - 480 * logicalScale)
        func scaled(_ rect: CGRect) -> CGRect {
            CGRect(x: logicalOrigin.x + rect.minX * logicalScale,
                   y: logicalOrigin.y + rect.minY * logicalScale,
                   width: rect.width * logicalScale, height: rect.height * logicalScale)
        }
        textScroll.frame = scaled(CGRect(x: 16, y: 414, width: 355, height: 62))
        textView.font = .systemFont(ofSize: max(9, 12 * logicalScale))
        textView.setFrameSize(NSSize(width: textScroll.contentSize.width,
                                     height: max(textScroll.contentSize.height, textView.frame.height)))
        let p = definition.nextPosition ?? CGPoint(x: 380, y: 447)
        nextButton.frame = scaled(CGRect(origin: p, size: nextArt?.size ?? NSSize(width: 72, height: 26)))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        context.cgContext.translateBy(x: logicalOrigin.x, y: logicalOrigin.y)
        context.cgContext.scaleBy(x: logicalScale, y: logicalScale)
        context.imageInterpolation = .none
        if let panel {
            // Full-screen transparent art retains its native origin; compact
            // message strips align to the bottom of the 640x480 canvas.
            panel.draw(in: CGRect(x: 0, y: max(0, 480 - panel.size.height),
                                  width: panel.size.width, height: panel.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1,
                       respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedWhite: 0.08, alpha: 0.92).setFill()
            CGRect(x: 8, y: 409, width: 445, height: 71).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        if textScroll.frame.contains(local) { return super.hitTest(point) }
        if !nextButton.isHidden, nextButton.frame.contains(local) { return super.hitTest(point) }
        // Consume the entire message strip, including gaps around the controls.
        let strip = CGRect(x: logicalOrigin.x, y: logicalOrigin.y + 409 * logicalScale,
                           width: 453 * logicalScale, height: 71 * logicalScale)
        return strip.contains(local) ? self : nil
    }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    static func image(_ path: String?, resources: GameResources) -> NSImage? {
        guard let path, let data = try? resources.data(at: path, maximumBytes: 8_000_000),
              let bitmap = try? PalettedBMP(data: data),
              let provider = CGDataProvider(data: Data(bitmap.blackKeyedRGBA()) as CFData),
              let cg = CGImage(width: bitmap.width, height: bitmap.height,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: bitmap.width, height: bitmap.height))
    }
}
#endif
