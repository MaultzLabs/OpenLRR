#if os(macOS)
import AppKit

/// Initial objective overlay only. All art, text and fonts come from the user's
/// archives; unavailable assets are diagnosed, never replaced with new artwork.
final class OriginalMissionBriefingUI: NSView {
    let definition: OriginalMissionBriefingDefinition
    let text: OriginalMissionBriefingText
    let textLayout: OriginalMissionBriefingLayout
    private(set) var state: OriginalMissionBriefingState
    private(set) var diagnostics: [String] = []
    private let panel: NSImage?
    private let nextArt: NSImage?
    private let previousArt: NSImage?
    private let bodyFont: OriginalBitmapFont?
    private let headingFont: OriginalBitmapFont?
    private var input: OriginalMissionBriefingInput
    private var eventMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []
    private var cancelled = false
    var onDismiss: (() -> Void)?
    var onExit: (() -> Void)?
    var originalCursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    var isActive: Bool { state.isActive && !cancelled }
    var bodyFontCellSize: CGSize? { bodyFont.map { CGSize(width: $0.cellWidth, height: $0.cellHeight) } }
    var headingFontCellSize: CGSize? { headingFont.map { CGSize(width: $0.cellWidth, height: $0.cellHeight) } }
    var headingFrame: CGRect {
        let rawWidth = headingFont?.layout(definition.headingBeforeUnderscoreReplacement ?? "")?.width
        return rawWidth.flatMap { textLayout.headingFrame(measuredRawWidth: Double($0)) } ?? textLayout.headingArea
    }
    // SetStatus drains the opening click before setting the BRIEFING flag.
    var objectiveShowing: Bool { isActive && state.isShowing }
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var transform: OriginalHUDTransform { OriginalHUDTransform(size: bounds.size) }

    init(definition: OriginalMissionBriefingDefinition, text: OriginalMissionBriefingText,
         resources: GameResources, openingInput: OriginalMissionBriefingInput) throws {
        self.definition = definition
        self.text = text
        textLayout = OriginalMissionBriefingLayout(definition: definition, text: text)
        input = openingInput
        panel = Self.image(definition.panel?.path, transparency: definition.panel?.transparency ?? .paletteZero,
                           resources: resources)
        nextArt = Self.image(definition.nextButtonPath, transparency: .rgb(0, 0, 0), resources: resources)
        previousArt = Self.image(definition.previousArrowPath, transparency: .rgb(0, 0, 0), resources: resources)
        let previousHitArt = Self.image(definition.previousHitTestPath, transparency: .rgb(0, 0, 0), resources: resources)
        bodyFont = OriginalBitmapFont.load(OriginalMissionBriefingDefinition.bodyFontPath, resources: resources)
        headingFont = OriginalBitmapFont.load(OriginalMissionBriefingDefinition.headingFontPath, resources: resources)
        state = try OriginalMissionBriefingState(pageCount: text.pages.count, nextButtonSize: nextArt?.size,
                                                previousHitTestSize: previousHitArt?.size, openingInput: openingInput)
        super.init(frame: .zero)
        if panel == nil { diagnostics.append("Original ObjectiveImage640x480 unavailable") }
        if bodyFont == nil { diagnostics.append("Original MBriefFONT.bmp unavailable; text uses diagnostic system font") }
        if headingFont == nil { diagnostics.append("Original MBriefFONT2.bmp unavailable; text uses diagnostic system font") }
        if nextArt == nil && text.pages.count > 1 { diagnostics.append("Original Next bitmap unavailable; use Space") }
        if previousArt == nil || previousHitArt == nil { diagnostics.append("Original Previous art/hit bitmap unavailable") }
        if text.body == nil { diagnostics.append("No Objective: text for \(definition.shortLevelName)") }
        if definition.continuePromptHasImage {
            diagnostics.append("Text_SpaceToContinue image/SFX variant not yet rendered; original prompt text only")
        }
        toolTip = diagnostics.joined(separator: "\n")
        setAccessibilityLabel(definition.heading ?? "Original mission briefing")
    }
    required init?(coder: NSCoder) { nil }
    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopMonitoring()
        guard window != nil, isActive else { return }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification] {
            focusObservers.append(NotificationCenter.default.addObserver(forName: name, object: window,
                queue: .main) { [weak self] _ in self?.synchronizeInput(Self.heldInput()) })
        }
        // A mission icon opens on mouseDown. Its mouseUp can still target the
        // old menu view: consume it here instead of trusting responder routing.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp, .leftMouseDragged, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged, .scrollWheel,
            .magnify, .rotate, .keyDown, .keyUp]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                return self.consume(event) ? nil : event
            }
    }

    /// Exit is not dismissal: no ObjectiveSwitch signal or gameplay handoff.
    func cancel() {
        cancelled = true
        isHidden = true
        stopMonitoring()
    }

    private func stopMonitoring() {
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
        focusObservers.removeAll()
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
    }

    static func heldInput() -> OriginalMissionBriefingInput {
        let buttons = NSEvent.pressedMouseButtons
        return OriginalMissionBriefingInput(
            spaceDown: CGEventSource.keyState(.combinedSessionState, key: 49),
            leftDown: buttons & 1 != 0, rightDown: buttons & 2 != 0)
    }

    /// Poll only to drain the launch gesture when AppKit did not route its
    /// release to this view (for example on focus changes). Ordinary advances
    /// remain event-driven, including very short press/release pairs.
    func drainOpeningInput() {
        guard state.phase == .drainingOpeningMouse else { return }
        apply(Self.heldInput())
    }

    func synchronizeInput(_ sample: OriginalMissionBriefingInput) {
        guard isActive else { return }
        input = sample
        state.synchronizeInput(sample)
        needsDisplay = true
    }

    @discardableResult
    func apply(_ sample: OriginalMissionBriefingInput) -> OriginalMissionBriefingState.Change {
        guard isActive else { return .none }
        input = sample
        let change = state.update(sample)
        needsDisplay = true
        if change == .dismissed {
            isHidden = true
            stopMonitoring()
            onDismiss?()
        }
        return change
    }

    /// Returns true only when the event belongs to the modal mission surface.
    /// Utility-bar Back/quit remains available; closing releases are consumed
    /// even though the callback hides the overlay during this method.
    @discardableResult
    func consume(_ event: NSEvent) -> Bool {
        guard isActive else { return false }
        if event.type == .keyDown || event.type == .keyUp {
            if event.keyCode == 49 && event.type == .keyUp {
                input.spaceDown = false
                apply(input)
                return !event.modifierFlags.contains(.command)
            }
            if event.modifierFlags.contains(.command) { return false }
            if event.keyCode == 53 && event.type == .keyDown { onExit?(); return true }
            if event.keyCode == 49 {
                if event.type == .keyDown && event.isARepeat { return true }
                input.spaceDown = event.type == .keyDown
                apply(input)
            }
            return true // Never move the cave camera underneath the briefing.
        }
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) || state.phase == .drainingOpeningMouse else { return false }
        input.pointer = transform.logical(point)
        switch event.type {
        case .leftMouseDown: input.leftDown = true
        case .leftMouseUp: input.leftDown = false
        case .rightMouseDown: input.rightDown = true
        case .rightMouseUp: input.rightDown = false
        default: break
        }
        apply(input)
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isActive, !isHidden else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: originalCursor ?? .arrow) }
    override func mouseDown(with event: NSEvent) { consume(event) }
    override func mouseUp(with event: NSEvent) { consume(event) }
    override func rightMouseDown(with event: NSEvent) { consume(event) }
    override func rightMouseUp(with event: NSEvent) { consume(event) }
    override func keyDown(with event: NSEvent) { consume(event) }
    override func keyUp(with event: NSEvent) { consume(event) }
    override func scrollWheel(with event: NSEvent) {}
    override func magnify(with event: NSEvent) {}
    override func rotate(with event: NSEvent) {}

    override func draw(_ dirtyRect: NSRect) {
        guard isActive, let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        let t = transform
        context.cgContext.translateBy(x: t.origin.x, y: t.origin.y)
        context.cgContext.scaleBy(x: t.scale, y: t.scale)
        context.imageInterpolation = .none
        func drawImage(_ image: NSImage?, at point: CGPoint) {
            guard let image else { return }
            image.draw(in: CGRect(origin: point, size: image.size), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        drawImage(panel, at: definition.panel?.position ?? .zero)
        drawText(text.pages[state.pageIndex], font: bodyFont, frame: textLayout.body, centered: false)
        if let begin = text.beginText { drawText(begin, font: headingFont, frame: textLayout.begin, centered: true) }
        if let title = definition.heading {
            drawText(title, font: headingFont, frame: headingFrame, centered: true)
        }
        if state.hasNextPage { drawImage(nextArt, at: OriginalMissionBriefingLayout.nextPosition) }
        if state.hasPreviousPage { drawImage(previousArt, at: OriginalMissionBriefingLayout.previousPosition) }
        if !diagnostics.isEmpty {
            (diagnostics.joined(separator: " · ") as NSString).draw(
                in: CGRect(x: 15, y: 355, width: 610, height: 60),
                withAttributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.systemYellow])
        }
    }

    private func drawText(_ value: String, font: OriginalBitmapFont?, frame: CGRect, centered: Bool) {
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        guard let font else {
            context.cgContext.clip(to: frame) // Diagnostic fallback only.
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = centered ? .center : .left
            (value as NSString).draw(in: frame, withAttributes: [.font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
            return
        }
        // TextWindow draws whole glyphs without clipping to its text rect;
        // oversized glyphs and the byte-203 caret may extend beyond it.
        guard let lines = OriginalBriefingTextLayout.make(text: value,
            characterWidths: font.characterWidths, lineHeight: font.cellHeight,
            width: Int(frame.width), height: Int(frame.height), centered: centered) else { return }
        for line in lines {
            font.draw(line.layout, at: CGPoint(x: frame.minX + CGFloat(line.x), y: frame.minY + CGFloat(line.y)))
        }
    }

    static func image(_ path: String?, transparency: OriginalMissionBriefingDefinition.Transparency,
                      resources: GameResources) -> NSImage? {
        guard let path, let data = try? resources.data(at: path, maximumBytes: 8_000_000),
              let bitmap = try? PalettedBMP(data: data) else { return nil }
        let pixels = rgba(bitmap, transparency: transparency)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: bitmap.width, height: bitmap.height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: bitmap.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: CGSize(width: bitmap.width, height: bitmap.height))
    }

    static func rgba(_ bitmap: PalettedBMP, transparency: OriginalMissionBriefingDefinition.Transparency) -> [UInt8] {
        switch transparency {
        case .paletteZero:
            // Image_SetPenZeroTrans keys the COLOR of palette zero, including
            // duplicate palette entries with that RGB, not just index zero.
            return rgba(bitmap, transparency: .rgb(bitmap.paletteZeroRGB[0], bitmap.paletteZeroRGB[1], bitmap.paletteZeroRGB[2]))
        case .rgb(let r, let g, let b):
            var pixels = bitmap.rgba
            for index in stride(from: 0, to: pixels.count, by: 4) {
                pixels[index + 3] = pixels[index] == r && pixels[index + 1] == g && pixels[index + 2] == b ? 0 : 255
            }
            return pixels
        }
    }
}
#endif
