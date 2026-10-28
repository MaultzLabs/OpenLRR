#if os(macOS)
import AppKit
import Foundation

/// A native, interactive overhead inspection of an ORIGINAL retail mission.
/// Every tile comes from the user's three required MAP files. This deliberately
/// does not impersonate the original 3D engine or invent functional units.
final class NativeLevelView: NSView {
    let world: LevelWorld
    var excavationState: NativeExcavationState?
    var onExit: (() -> Void)?
    var missionInputBlocked = false
    var originalCursor: NSCursor? {
        didSet { if let window { window.invalidateCursorRects(for: self) } }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: originalCursor ?? .arrow)
    }
    private var cameraX: CGFloat
    private var cameraY: CGFloat
    private var tileSize: CGFloat = 23
    private var selected: LevelWorld.Tile?
    private var previousDragPoint: CGPoint?
    var tutorialInputPolicy = NativeTutorialInputPolicy.unrestricted

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, world: LevelWorld) {
        self.world = world
        let initial = world.initialCameraTile
        cameraX = CGFloat(initial.x) + 0.5
        cameraY = CGFloat(initial.y) + 0.5
        super.init(frame: frameRect)
        wantsLayer = true
        needsDisplay = true
    }

    required init?(coder: NSCoder) { nil }

    private var sceneCenter: CGPoint {
        CGPoint(x: bounds.midX, y: bounds.midY + 16)
    }

    private func tileFrame(x: Int, y: Int) -> CGRect {
        let center = sceneCenter
        return CGRect(x: center.x + (CGFloat(x) - cameraX) * tileSize,
                      y: center.y + (CGFloat(y) - cameraY) * tileSize,
                      width: tileSize, height: tileSize)
    }

    private func tile(at point: CGPoint) -> LevelWorld.Tile? {
        let center = sceneCenter
        let x = Int(floor((point.x - center.x) / tileSize + cameraX))
        let y = Int(floor((point.y - center.y) / tileSize + cameraY))
        return excavationState?.tile(x: x, y: y) ?? world.tile(x: x, y: y)
    }

    private func tileColor(_ tile: LevelWorld.Tile) -> NSColor {
        let terrain = tile.terrain
        let cavern = tile.excavation
        if cavern == .hidden || cavern == .hiddenSlugHole {
            return NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.14, alpha: 1)
        }
        if terrain == .lava {
            return NSColor(calibratedRed: 0.90, green: 0.30, blue: 0.12, alpha: 1)
        }
        if terrain == .water || terrain == .lake {
            return NSColor(calibratedRed: 0.13, green: 0.39, blue: 0.74, alpha: 1)
        }
        if cavern.isCavern {
            let boost = min(CGFloat(tile.heightCode) / 220, 0.11)
            return NSColor(calibratedRed: 0.24 + boost, green: 0.30 + boost,
                           blue: 0.28 + boost, alpha: 1)
        }
        switch terrain {
        case .immovable: return NSColor(calibratedRed: 0.30, green: 0.33, blue: 0.36, alpha: 1)
        case .hard: return NSColor(calibratedRed: 0.46, green: 0.46, blue: 0.47, alpha: 1)
        case .medium: return NSColor(calibratedRed: 0.61, green: 0.47, blue: 0.30, alpha: 1)
        case .dirt, .soil: return NSColor(calibratedRed: 0.61, green: 0.38, blue: 0.22, alpha: 1)
        case .oreSeam: return NSColor(calibratedRed: 0.47, green: 0.55, blue: 0.63, alpha: 1)
        case .crystalSeam: return NSColor(calibratedRed: 0.18, green: 0.80, blue: 0.66, alpha: 1)
        case .rechargeSeam: return NSColor(calibratedRed: 0.36, green: 0.67, blue: 0.28, alpha: 1)
        case .tunnel, .rubble, .reinforcement, .path, .slugHole,
             .undiscovered, .cavern:
            return NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.29, alpha: 1)
        case .unknown, .lava, .water, .lake:
            return NSColor(calibratedWhite: 0.18, alpha: 1)
        }
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat,
                          size: CGFloat = 13, weight: NSFont.Weight = .regular,
                          color: NSColor = .white) {
        (text as NSString).draw(at: CGPoint(x: x, y: y),
            withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
                             .foregroundColor: color])
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.045, green: 0.058, blue: 0.062, alpha: 1).setFill()
        bounds.fill()

        // Frustum-cull the drawn world; the entire source map remains in memory
        // and no random art or terrain is generated.
        let center = sceneCenter
        let startX = max(0, Int(floor(cameraX - center.x / tileSize)) - 1)
        let endX = min(world.width - 1,
                       Int(ceil(cameraX + (bounds.width - center.x) / tileSize)) + 1)
        let startY = max(0, Int(floor(cameraY - center.y / tileSize)) - 1)
        let endY = min(world.height - 1,
                       Int(ceil(cameraY + (bounds.height - center.y) / tileSize)) + 1)
        if endX >= startX && endY >= startY {
            for y in startY...endY {
                for x in startX...endX {
                    guard let tile = excavationState?.tile(x: x, y: y) ?? world.tile(x: x, y: y) else { continue }
                    let rect = tileFrame(x: x, y: y)
                    tileColor(tile).setFill()
                    rect.fill()
                    NSColor(calibratedWhite: 0.02, alpha: 0.4).setStroke()
                    NSBezierPath(rect: rect).stroke()
                }
            }
        }

        if let old = selected,
           let tile = excavationState?.tile(x: old.x, y: old.y) ?? world.tile(x: old.x, y: old.y) {
            let outline = tileFrame(x: tile.x, y: tile.y).insetBy(dx: -1.5, dy: -1.5)
            NSColor.systemYellow.setStroke()
            let selection = NSBezierPath(rect: outline)
            selection.lineWidth = 2.5
            selection.stroke()
        }

        // Overlay instructions and diagnostics do not become part of the game.
        let banner = CGRect(x: 0, y: 0, width: bounds.width, height: 75)
        NSColor(calibratedWhite: 0.075, alpha: 0.94).setFill()
        banner.fill()
        drawText(world.title, x: 18, y: 12, size: 19, weight: .bold)
        drawText("ORIGINAL TERRAIN INSPECTION — 3D GAMEPLAY NOT PORTED",
                 x: 18, y: 40, size: 12, color: NSColor.systemOrange)
        let footer = CGRect(x: 0, y: bounds.maxY - 57, width: bounds.width, height: 57)
        NSColor(calibratedWhite: 0.075, alpha: 0.94).setFill()
        footer.fill()
        let detail: String
        if let old = selected,
           let tile = excavationState?.tile(x: old.x, y: old.y) ?? world.tile(x: old.x, y: old.y) {
            detail = "Tile (\(tile.x), \(tile.y))   \(tile.terrain.rawValue)   " +
                "\(tile.excavation.rawValue)   Height \(tile.heightCode)"
        } else {
            detail = "Original \(world.width) × \(world.height) tile map. Click any tile for its values."
        }
        drawText(detail, x: 18, y: bounds.maxY - 49, size: 12, weight: .medium)
        drawText("Drag: pan    Scroll/+/-: zoom    Arrows/WASD: move    R: recenter    Esc: close",
                 x: 18, y: bounds.maxY - 28, size: 11,
                 color: NSColor(calibratedWhite: 0.72, alpha: 1))
    }

    private func constrainCamera() {
        cameraX = max(0.5, min(CGFloat(world.width) - 0.5, cameraX))
        cameraY = max(0.5, min(CGFloat(world.height) - 0.5, cameraY))
    }

    private func zoomBy(_ multiplier: CGFloat) {
        tileSize = max(5, min(85, tileSize * multiplier))
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard !missionInputBlocked else { return }
        let point = convert(event.locationInWindow, from: nil)
        if tutorialInputPolicy.canClickMap &&
           point.y >= 75 && point.y < bounds.height - 57 {
            selected = tile(at: point)
        }
        previousDragPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !missionInputBlocked else { return }
        let point = convert(event.locationInWindow, from: nil)
        if tutorialInputPolicy.canMoveCamera, let last = previousDragPoint {
            cameraX -= (point.x - last.x) / tileSize
            cameraY -= (point.y - last.y) / tileSize
            constrainCamera()
        }
        previousDragPoint = point
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        previousDragPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard !missionInputBlocked else { return }
        guard tutorialInputPolicy.canMoveCamera else { return }
        zoomBy(event.scrollingDeltaY > 0 ? 1.12 : 1.0 / 1.12)
    }

    override func magnify(with event: NSEvent) {
        guard !missionInputBlocked else { return }
        guard tutorialInputPolicy.canMoveCamera else { return }
        zoomBy(1 + event.magnification)
    }

    override func keyDown(with event: NSEvent) {
        guard !missionInputBlocked else { return }
        // Mac Escape always returns to the native menu, including when the
        // retail NERPs script has locked movement during a tutorial prompt.
        if event.keyCode == 53 { onExit?(); return }
        guard tutorialInputPolicy.canMoveCamera else { return }
        let step = max(1, 35 / tileSize)
        switch event.keyCode {
        case 123, 0: cameraX -= step // Left / A
        case 124, 2: cameraX += step // Right / D
        case 125, 1: cameraY += step // Down / S
        case 126, 13: cameraY -= step // Up / W
        case 24, 69: zoomBy(1.2)  // Plus
        case 27, 78: zoomBy(1 / 1.2) // Minus
        case 15: // R
            let initial = world.initialCameraTile
            cameraX = CGFloat(initial.x) + 0.5
            cameraY = CGFloat(initial.y) + 0.5
        default:
            super.keyDown(with: event)
            return
        }
        constrainCamera()
        needsDisplay = true
    }
}
#endif
