import Foundation

/// Retail Panels640x480 entries: image,xout,yout,xin,yin. Positions are
/// retained verbatim; native windows scale one 640x480 canvas uniformly.
struct OriginalMissionPanelDefinition {
    let name: String
    let image: String
    let open: CGPoint
    let closed: CGPoint

    static func parse(name: String, value: String) -> Self? {
        let parts = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5, parts[0].lowercased().hasSuffix(".bmp"),
              let open = OriginalMissionMessageDefinition.point(parts[1] + "," + parts[2]),
              let closed = OriginalMissionMessageDefinition.point(parts[3] + "," + parts[4]) else { return nil }
        return Self(name: name.lowercased(), image: parts[0], open: open, closed: closed)
    }

    static func load(_ config: LegoConfig?) -> [Self] {
        // Messages have their own renderer. Interactive sliding windows are
        // intentionally excluded until their state/contents are implemented.
        let order = ["panel_messagesside", "panel_cameracontrol", "panel_toppanel", "panel_crystalsidebar", "panel_infodock"]
        let fixed = Set(order)
        return (config?.settingsUnderGame(["Panels640x480"]) ?? []).compactMap { setting in
            guard fixed.contains(setting.name) else { return nil }
            return parse(name: setting.name, value: setting.value)
        }.sorted { order.firstIndex(of: $0.name)! < order.firstIndex(of: $1.name)! }
    }
}

struct OriginalHUDTransform {
    let scale: CGFloat
    let origin: CGPoint
    init(size: CGSize) {
        scale = max(0.001, min(size.width / 640, size.height / 480))
        origin = CGPoint(x: (size.width - 640 * scale) / 2, y: size.height - 480 * scale)
    }
    func logical(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }
    func screen(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale,
               width: rect.width * scale, height: rect.height * scale)
    }
}

struct OriginalRotationControl {
    struct Overlay { let image: String; let position: CGPoint }
    let center: CGPoint
    let radius: CGFloat
    let overlays: [String: Overlay]
    init?(config: LegoConfig?) {
        func value(_ name: String) -> String? { config?.valueUnderGame(["PanelRotationControl", name]) }
        guard let x = value("CenterPositionX"), let y = value("CenterPositionY"),
              let center = OriginalMissionMessageDefinition.point(x + "," + y),
              let rawRadius = value("Radius"), let radius = Double(rawRadius),
              radius.isFinite, radius > 0, radius <= 128 else { return nil }
        self.center = center
        self.radius = radius
        var overlays: [String: Overlay] = [:]
        for direction in ["Left", "Right", "Up", "Down"] {
            guard let raw = value(direction + "Image") else { continue }
            let fields = raw.components(separatedBy: ",")
            guard fields.count == 3, fields[0].lowercased().hasSuffix(".bmp"),
                  let p = OriginalMissionMessageDefinition.point(fields[1] + "," + fields[2]) else { continue }
            overlays[direction] = Overlay(image: fields[0], position: p)
        }
        self.overlays = overlays
    }
    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - center.x, point.y - center.y) <= radius
    }
    /// Matches the circular normalization/clamp contract in Panels.h.
    /// Dragging outside the disk clamps magnitude instead of accelerating.
    func normalized(_ point: CGPoint) -> CGPoint {
        let x = (point.x - center.x) / radius, y = (point.y - center.y) / radius
        let length = max(1, hypot(x, y))
        return CGPoint(x: x / length, y: y / length)
    }
}

#if os(macOS)
import AppKit

final class OriginalMissionPanels: NSView {
    private struct Asset {
        let definition: OriginalMissionPanelDefinition
        let image: NSImage
        let width: Int
        let height: Int
        let pixels: [UInt8]
        func contains(_ point: CGPoint) -> Bool {
            let x = Int(floor(point.x - definition.open.x)), y = Int(floor(point.y - definition.open.y))
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return pixels[(y * width + x) * 4 + 3] != 0
        }
    }
    private let assets: [Asset]
    private let rotation: OriginalRotationControl?
    private var arrows: [String: NSImage] = [:]
    private var controlVector = CGPoint.zero
    private var trackingRotation = false
    private var repeatTimer: Timer?
    private var previousTick: TimeInterval?
    var onCameraControl: ((CGPoint, Double) -> Void)?
    var cameraPermitted = true { didSet { if !cameraPermitted { stopControl() } } }
    var originalCursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    override var isFlipped: Bool { true }
    private var transform: OriginalHUDTransform { OriginalHUDTransform(size: bounds.size) }

    init(resources: GameResources, config: LegoConfig?) {
        assets = OriginalMissionPanelDefinition.load(config).compactMap { definition in
            guard let bytes = try? resources.data(at: definition.image, maximumBytes: 8_000_000),
                  let bitmap = try? PalettedBMP(data: bytes),
                  let image = OriginalMissionMessageUI.image(definition.image, resources: resources) else { return nil }
            return Asset(definition: definition, image: image, width: bitmap.width, height: bitmap.height, pixels: bitmap.blackKeyedRGBA())
        }
        rotation = OriginalRotationControl(config: config)
        super.init(frame: .zero)
        if let rotation {
            for (direction, overlay) in rotation.overlays {
                arrows[direction] = OriginalMissionMessageUI.image(overlay.image, resources: resources)
            }
        }
    }
    required init?(coder: NSCoder) { nil }
    deinit { repeatTimer?.invalidate() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: originalCursor ?? .arrow) }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stopControl()
        super.viewWillMove(toWindow: newWindow)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let p = transform.logical(convert(point, from: superview))
        if hasCameraArt, rotation?.contains(p) == true { return self }
        return assets.contains { $0.contains(p) } ? self : nil
    }
    private var hasCameraArt: Bool { assets.contains { $0.definition.name == "panel_cameracontrol" } }
    override func mouseDown(with event: NSEvent) {
        let p = transform.logical(convert(event.locationInWindow, from: nil))
        guard cameraPermitted, hasCameraArt, let rotation, rotation.contains(p) else { return }
        trackingRotation = true
        controlVector = rotation.normalized(p)
        previousTick = ProcessInfo.processInfo.systemUptime
        repeatTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tickControl() }
        RunLoop.main.add(timer, forMode: .common)
        repeatTimer = timer
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard trackingRotation, let rotation else { return }
        controlVector = rotation.normalized(transform.logical(convert(event.locationInWindow, from: nil)))
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { stopControl() }
    override func rightMouseDown(with event: NSEvent) { stopControl() }
    private func tickControl() {
        guard trackingRotation, cameraPermitted, window?.isKeyWindow == true else { stopControl(); return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = min(0.05, max(0, now - (previousTick ?? now)))
        previousTick = now
        onCameraControl?(controlVector, elapsed)
    }
    private func stopControl() {
        repeatTimer?.invalidate(); repeatTimer = nil
        previousTick = nil; trackingRotation = false; controlVector = .zero
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        for asset in assets {
            let rect = CGRect(origin: asset.definition.open, size: asset.image.size)
            asset.image.draw(in: transform.screen(rect), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
        guard trackingRotation, let rotation else { return }
        let active = [("Left", controlVector.x < -0.05), ("Right", controlVector.x > 0.05),
                      ("Up", controlVector.y < -0.05), ("Down", controlVector.y > 0.05)]
        for (direction, enabled) in active where enabled {
            guard let overlay = rotation.overlays[direction], let image = arrows[direction] else { continue }
            image.draw(in: transform.screen(CGRect(origin: overlay.position, size: image.size)), from: .zero,
                       operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
#endif
