import Foundation

/// Original interface names from GameCommon.h; assets always come from CFG.
struct OriginalMissionCommand {
    let id: String
    let title: String
    let iconPath: String?
    let detail: String
    let enabled: Bool
}

struct OriginalMissionCommandCatalog {
    let config: LegoConfig?
    enum Page: Equatable {
        case main, buildings, raider, wall, firstPerson
        // Interface_NotMainOrFirstPersonMenu excludes both of these pages.
        var showsBack: Bool { self != .main && self != .firstPerson }
    }

    func icon(_ name: String) -> String? {
        OriginalMissionMessageDefinition.firstBitmapPath(config?.valueUnderGame(["InterfaceImages", "Interface_MenuItem_" + name]))
    }

    func commands(on page: Page, hasRaider: Bool) -> [OriginalMissionCommand] {
        func item(_ id: String, _ title: String, _ enabled: Bool, _ detail: String) -> OriginalMissionCommand {
            OriginalMissionCommand(id: id, title: title, iconPath: icon(id), detail: detail, enabled: enabled)
        }
        switch page {
        case .main:
            return [item("TeleportMan", "Teleport Rock Raider", false, "Raider teleporting is not available in this build."),
                    item("BuildBuilding", "Buildings", !(config?.settingsUnderGame(["BuildingTypes"]).isEmpty ?? true), "Browse the original building catalog and costs."),
                    item("BuildSmallVehicle", "Small vehicles", false, "Vehicle transport is not available in this build."),
                    item("BuildLargeVehicle", "Large vehicles", false, "Vehicle transport is not available in this build.")]
        case .buildings:
            return (config?.settingsUnderGame(["BuildingTypes"]) ?? []).map { entry in
                let title = (config?.valueUnderGame(["ObjectNames", entry.name]) ?? entry.name).replacingOccurrences(of: "_", with: " ")
                var details: [String] = []
                for (key, label) in [("CostOre", "ore"), ("CostCrystal", "crystals")] {
                    if let raw = config?.valueUnderGame(["Stats", entry.name, key]),
                       let cost = Int(raw), (0...1_000_000).contains(cost) { details.append("\(cost) \(label)") }
                }
                details.append("Construction is not available in this build.")
                return OriginalMissionCommand(id: "building:" + entry.name, title: title,
                    iconPath: OriginalMissionMessageDefinition.firstBitmapPath(config?.valueUnderGame(["InterfaceBuildImages", entry.name])),
                    detail: details.joined(separator: " · "), enabled: false)
            }
        case .wall:
            return [item("Dig", "Drill", hasRaider, hasRaider ? "Drill this wall with the selected Rock Raider." : "Select a Rock Raider before choosing a wall."),
                    item("DeselectDig", "Cancel drilling", hasRaider, "Cancel the selected Raider's current order."),
                    item("Reinforce", "Reinforce wall", false, "Wall reinforcement is not available in this build."),
                    item("Dynamite", "Dynamite", false, "Explosives are not available in this build.")]
        case .raider:
            return [item("GotoFirstPerson", "First-person view", true, "Control this Rock Raider directly. F also switches view."),
                    item("GetTool", "Get tools", false, "Tool collection is not available in this build."),
                    item("TrainSkill", "Train Rock Raider", false, "Training is not available in this build."),
                    item("UpgradeMan", "Upgrade Rock Raider", false, "Raider upgrades are not available in this build.")]
        case .firstPerson:
            return [item("GotoTopView", "Overhead view", true, "Return to the overhead camera. F or Escape also returns.")]
        }
    }

    struct BackButton {
        let size: CGSize
        let hover: String
        let pressed: String
        let title: String
    }
    var backButton: BackButton? {
        guard let raw = config?.valueUnderGame(["InterfaceBackButton"]) ?? config?.valueUnderGame(["Main", "InterfaceBackButton"]) else { return nil }
        let fields = raw.components(separatedBy: raw.contains(",") ? "," : ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 5,
              let dimensions = OriginalMissionMessageDefinition.point(fields[0] + "," + fields[1]),
              dimensions.x > 0, dimensions.y > 0, dimensions.x <= 128, dimensions.y <= 128,
              fields[2].lowercased().hasSuffix(".bmp"), fields[3].lowercased().hasSuffix(".bmp") else { return nil }
        return BackButton(size: CGSize(width: dimensions.x, height: dimensions.y), hover: fields[2], pressed: fields[3], title: fields[4].replacingOccurrences(of: "_", with: " "))
    }

    /// Interface_LoadItemPanels / Interface_FUN_0041b3c0 (retail interface.c):
    /// these are surround ART offsets from the menu origin, not icon offsets.
    /// Back has its own independent offset from that same origin.
    struct Surround {
        let image: String
        let artOffset: CGPoint
        let back: CGPoint?
    }
    func surround(count: Int, hasBack: Bool) -> Surround? {
        guard (1...11).contains(count),
              let raw = config?.valueUnderGame(["InterfaceSurroundImages", String(count)]) else { return nil }
        let fields = raw.components(separatedBy: raw.contains(",") ? "," : ":").map { $0.trimmingCharacters(in: .whitespaces) }
        let offset = hasBack ? 0 : 5
        guard fields.count >= offset + 3, fields[offset].lowercased().hasSuffix(".bmp"),
              let position = OriginalMissionMessageDefinition.point(fields[offset + 1] + "," + fields[offset + 2]) else { return nil }
        let back = hasBack && fields.count >= 5 ? OriginalMissionMessageDefinition.point(fields[3] + "," + fields[4]) : nil
        return Surround(image: fields[offset], artOffset: position, back: back)
    }
}

/// Logical 640x480 geometry, shared by rendering and input. Icons start at the
/// GameState.cpp Interface_Initialise(565,18) origin and stack by bitmap height.
/// A negative surround offset must never move or clip the command icons.
struct OriginalMissionCommandLayout {
    static let menuOrigin = CGPoint(x: 565, y: 18)
    let icons: [CGRect]
    let surround: CGRect?
    let back: CGRect?

    init(iconSizes: [CGSize], surround: OriginalMissionCommandCatalog.Surround?,
         surroundSize: CGSize?, backSize: CGSize?, showsBack: Bool) {
        let origin = Self.menuOrigin
        var y = origin.y
        icons = iconSizes.map { size in
            defer { y += size.height }
            return CGRect(x: origin.x, y: y, width: size.width, height: size.height)
        }
        if let surround, let surroundSize {
            self.surround = CGRect(x: origin.x + surround.artOffset.x,
                                   y: origin.y + surround.artOffset.y,
                                   width: surroundSize.width, height: surroundSize.height)
        } else {
            self.surround = nil
        }
        if showsBack, let backSize {
            let offset = surround?.back ?? CGPoint(x: 0, y: y - origin.y + 2)
            back = CGRect(x: origin.x + offset.x, y: origin.y + offset.y,
                          width: backSize.width, height: backSize.height)
        } else {
            back = nil
        }
    }
}

#if os(macOS)
import AppKit

/// Owns only command rectangles and opaque artwork, leaving cave input available.
/// Background/offsets use original CFG data; missing art gets native controls.
private final class MissionCommandButton: NSButton {
    var onHover: ((Bool) -> Void)?
    var hoverArt: NSImage?
    var pressedArt: NSImage?
    private var hovered = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true; onHover?(false) }
    override func rightMouseDown(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) {
        if let hoverArt {
            // The surround contains the idle Back image; CFG supplies only
            // the highlight and pressed overlays (Interface.h fields 2,3).
            if hovered || isHighlighted {
                NSGraphicsContext.current?.imageInterpolation = .none
                (isHighlighted ? (pressedArt ?? hoverArt) : hoverArt).draw(in: bounds,
                    from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.4,
                    respectFlipped: true, hints: nil)
            }
        } else { super.draw(dirtyRect) }
        if hovered && isEnabled {
            // Interface_DrawHoverOutline uses a two-pixel green outline.
            NSColor.green.setStroke()
            let outline = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
            outline.lineWidth = 2
            outline.stroke()
        }
    }
}

private final class MissionCommandDocument: NSView {
    override var isFlipped: Bool { true }
}

final class OriginalMissionCommands: NSView {
    private let catalog: OriginalMissionCommandCatalog
    private let resources: GameResources
    private let scroll = NSScrollView()
    private let document = MissionCommandDocument()
    private let heading = NSTextField(labelWithString: "")
    private let back = MissionCommandButton(title: "Back", target: nil, action: nil)
    private var buttons: [NSButton] = []
    private var definitions: [OriginalMissionCommand] = []
    private struct Art {
        let image: NSImage
        let width: Int
        let height: Int
        let pixels: [UInt8]
        func contains(_ point: CGPoint) -> Bool {
            let x = Int(floor(point.x)), y = Int(floor(point.y))
            guard x >= 0, y >= 0, x < width, y < height else { return false }
            return pixels[(y * width + x) * 4 + 3] != 0
        }
    }
    private var artCache: [String: Art] = [:]
    private var surroundArt: Art?
    private var surround: OriginalMissionCommandCatalog.Surround?
    private var page = OriginalMissionCommandCatalog.Page.main
    private var hasRaider = false
    private var permitted = true
    var onCommand: ((String) -> Void)?
    var onBack: (() -> Void)?
    private var visiblePanel = NSRect.zero
    private var commandLayout: OriginalMissionCommandLayout?
    private var transform: OriginalHUDTransform { OriginalHUDTransform(size: bounds.size) }
    var originalCursor: NSCursor? { didSet { window?.invalidateCursorRects(for: self) } }
    override var isFlipped: Bool { true }

    init(resources: GameResources, config: LegoConfig?) {
        self.resources = resources
        self.catalog = OriginalMissionCommandCatalog(config: config)
        super.init(frame: .zero)
        wantsLayer = true
        heading.textColor = .white
        heading.alignment = .center
        heading.lineBreakMode = .byTruncatingTail
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(heading)
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(scroll)
        back.target = self
        back.action = #selector(goBack)
        back.toolTip = "Return to the main command menu"
        back.setAccessibilityLabel("Back to main commands")
        addSubview(back)
        update(page: .main, hasRaider: false, permitted: true)
    }
    required init?(coder: NSCoder) { nil }
    override func resetCursorRects() { addCursorRect(bounds, cursor: originalCursor ?? .arrow) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {} // Never drill through the UI.

    private func art(_ path: String?) -> Art? {
        guard let path else { return nil }
        if let cached = artCache[path] { return cached }
        guard let data = try? resources.data(at: path, maximumBytes: 8_000_000),
              let bitmap = try? PalettedBMP(data: data),
              let image = OriginalMissionMessageUI.image(path, resources: resources) else { return nil }
        let result = Art(image: image, width: bitmap.width, height: bitmap.height,
                         pixels: bitmap.blackKeyedRGBA())
        artCache[path] = result
        return result
    }
    private func image(_ path: String?) -> NSImage? { art(path)?.image }

    func update(page: OriginalMissionCommandCatalog.Page, hasRaider: Bool, permitted: Bool) {
        let rebuild = self.page != page || self.hasRaider != hasRaider || buttons.isEmpty
        self.page = page
        self.hasRaider = hasRaider
        self.permitted = permitted
        if rebuild {
            buttons.forEach { $0.removeFromSuperview() }
            definitions = catalog.commands(on: page, hasRaider: hasRaider)
            surround = catalog.surround(count: definitions.count, hasBack: page.showsBack)
            surroundArt = art(surround?.image)
            buttons = definitions.enumerated().map { index, definition in
                let button = MissionCommandButton(title: definition.title, target: self, action: #selector(activate(_:)))
                button.tag = index
                button.toolTip = nil // Retail tooltips require the original renderer and CFG text.
                button.setAccessibilityLabel(definition.title)
                button.setAccessibilityHelp(definition.detail)
                button.font = .systemFont(ofSize: 10, weight: .medium)
                button.bezelStyle = .regularSquare
                if let art = image(definition.iconPath) {
                    button.image = art
                    button.title = ""
                    button.imageScaling = .scaleProportionallyUpOrDown
                    button.isBordered = false
                    // AppKit's highlight/dimming provides state feedback without
                    // guessing the order of undocumented optional CFG bitmaps.
                }
                if surroundArt != nil { addSubview(button) }
                else { document.addSubview(button) }
                return button
            }
            // Use transparent idle Back only with its original surround.
            let backDefinition = catalog.backButton
            back.hoverArt = surroundArt == nil ? nil : image(backDefinition?.hover)
            back.pressedArt = image(backDefinition?.pressed)
            back.toolTip = backDefinition?.title ?? "Back"
            scroll.contentView.scroll(to: .zero)
        }
        for (button, definition) in zip(buttons, definitions) { button.isEnabled = permitted && definition.enabled }
        back.isEnabled = permitted
        back.isHidden = !page.showsBack
        heading.stringValue = page == .buildings ? "Buildings" : page == .wall ? "Wall" : page == .raider ? "Rock Raider" : page == .firstPerson ? "First person" : "Commands"
        needsLayout = true
        needsDisplay = true
    }

    @objc private func activate(_ sender: NSButton) {
        guard !isHidden, permitted, definitions.indices.contains(sender.tag),
              buttons[sender.tag] === sender, sender.isEnabled, definitions[sender.tag].enabled else { return }
        onCommand?(definitions[sender.tag].id)
    }
    @objc private func goBack() {
        guard !isHidden, permitted, !back.isHidden, back.isEnabled else { return }
        onBack?()
    }

    override func layout() {
        super.layout()
        let transform = self.transform
        let scale = transform.scale
        let original = surroundArt != nil
        heading.isHidden = original
        scroll.isHidden = original
        // Do not cap bitmap dimensions: the original advances by each actual
        // image height. Text is an explicitly native missing-asset fallback.
        let sizes = buttons.map { $0.image?.size ?? CGSize(width: 67, height: 40) }
        // CFG hit dimensions remain authoritative even if a Back overlay BMP
        // is missing; only the native sidebar uses the native default size.
        let backSize = original ? (catalog.backButton?.size ?? CGSize(width: 67, height: 34)) : CGSize(width: 67, height: 34)
        if original {
            let layout = OriginalMissionCommandLayout(iconSizes: sizes, surround: surround,
                surroundSize: surroundArt?.image.size, backSize: backSize, showsBack: page.showsBack)
            commandLayout = layout
            for (button, rect) in zip(buttons, layout.icons) { button.frame = transform.screen(rect) }
            back.frame = layout.back.map { transform.screen($0) } ?? .zero
            visiblePanel = .zero
        } else {
            commandLayout = nil
            // Keep missing/malformed art usable, but confine its opaque native
            // sidebar to the same logical HUD canvas (including tall windows).
            let origin = OriginalMissionCommandLayout.menuOrigin
            heading.frame = transform.screen(CGRect(x: origin.x + 2, y: origin.y, width: 71, height: 20))
            let top = origin.y + 22
            let contentHeight = sizes.reduce(CGFloat(0)) { $0 + $1.height }
            let available = max(1, 390 - top - (back.isHidden ? 4 : backSize.height + 4))
            let scrollHeight = min(contentHeight, available)
            scroll.frame = transform.screen(CGRect(x: origin.x + 4, y: top, width: 71, height: max(1, scrollHeight)))
            document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width,
                                    height: max(scrollHeight, contentHeight) * scale)
            var y: CGFloat = 0
            for (button, size) in zip(buttons, sizes) {
                button.frame = NSRect(x: 0, y: y, width: min(document.bounds.width, size.width * scale), height: size.height * scale)
                y += size.height * scale
            }
            back.frame = transform.screen(CGRect(x: origin.x + 4, y: top + scrollHeight + 2,
                                                  width: min(71, backSize.width), height: backSize.height))
            let bottom = back.isHidden ? scroll.frame.maxY : back.frame.maxY
            let panelOrigin = transform.screen(CGRect(origin: origin, size: .zero)).origin
            visiblePanel = NSRect(x: panelOrigin.x, y: panelOrigin.y, width: 75 * scale,
                                  height: bottom - panelOrigin.y + 4 * scale)
        }
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if let layout = commandLayout, let art = surroundArt {
            // Retail tests Back first, then rectangular icon bounds, then the
            // nonblack surround pixels. Disabled controls still block the cave.
            if !back.isHidden, back.frame.contains(local) { return back }
            if let button = buttons.first(where: { $0.frame.contains(local) }) { return button }
            if let rect = layout.surround {
                let p = transform.logical(local)
                if art.contains(CGPoint(x: p.x - rect.minX, y: p.y - rect.minY)) { return self }
            }
            return nil
        }
        guard visiblePanel.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let art = surroundArt, let rect = commandLayout?.surround {
            art.image.draw(in: transform.screen(rect), from: .zero,
                           operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else if surroundArt == nil {
            NSColor(calibratedWhite: 0.08, alpha: 0.86).setFill()
            NSBezierPath(roundedRect: visiblePanel, xRadius: 5, yRadius: 5).fill()
        }
    }
}
#endif
