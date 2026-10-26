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
    enum Page: Equatable { case main, buildings, raider, wall, firstPerson }

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

    /// Interface_Globs documents the eight surround fields in Interface.h.
    struct Surround {
        let image: String
        let icons: CGPoint
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
        return Surround(image: fields[offset], icons: position, back: back)
    }
}

#if os(macOS)
import AppKit

/// Owns only its sidebar hit area, so cave input remains available elsewhere.
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
    private var artCache: [String: NSImage] = [:]
    private var surroundArt: NSImage?
    private var surround: OriginalMissionCommandCatalog.Surround?
    private var page = OriginalMissionCommandCatalog.Page.main
    private var hasRaider = false
    private var permitted = true
    var onCommand: ((String) -> Void)?
    var onBack: (() -> Void)?
    var logicalScale: CGFloat = 1 { didSet { needsLayout = true; needsDisplay = true } }
    private var visiblePanel = NSRect.zero
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

    private func image(_ path: String?) -> NSImage? {
        guard let path else { return nil }
        if let cached = artCache[path] { return cached }
        guard let result = OriginalMissionMessageUI.image(path, resources: resources) else { return nil }
        artCache[path] = result
        return result
    }

    func update(page: OriginalMissionCommandCatalog.Page, hasRaider: Bool, permitted: Bool) {
        let rebuild = self.page != page || self.hasRaider != hasRaider || buttons.isEmpty
        self.page = page
        self.hasRaider = hasRaider
        self.permitted = permitted
        if rebuild {
            buttons.forEach { $0.removeFromSuperview() }
            definitions = catalog.commands(on: page, hasRaider: hasRaider)
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
                document.addSubview(button)
                return button
            }
            surround = catalog.surround(count: definitions.count, hasBack: page != .main)
            surroundArt = image(surround?.image)
            // Use transparent idle Back only with its original surround.
            let backDefinition = catalog.backButton
            back.hoverArt = surroundArt == nil ? nil : image(backDefinition?.hover)
            back.pressedArt = image(backDefinition?.pressed)
            back.toolTip = backDefinition?.title ?? "Back"
            scroll.contentView.scroll(to: .zero)
        }
        for (button, definition) in zip(buttons, definitions) { button.isEnabled = permitted && definition.enabled }
        back.isEnabled = permitted
        back.isHidden = page == .main
        heading.stringValue = page == .buildings ? "Buildings" : page == .wall ? "Wall" : page == .raider ? "Rock Raider" : page == .firstPerson ? "First person" : "Commands"
        needsLayout = true
        needsDisplay = true
    }

    @objc private func activate(_ sender: NSButton) {
        guard permitted, definitions.indices.contains(sender.tag), definitions[sender.tag].enabled else { return }
        onCommand?(definitions[sender.tag].id)
    }
    @objc private func goBack() { if permitted { onBack?() } }

    override func layout() {
        super.layout()
        let scale = max(0.1, logicalScale)
        let original = surroundArt != nil
        heading.isHidden = original
        heading.frame = NSRect(x: 2, y: 0, width: max(1, bounds.width - 4), height: 20 * scale)
        let offset = original ? (surround?.icons ?? .zero) : CGPoint(x: 4, y: 22)
        let x = max(0, min(bounds.width - 1, offset.x * scale))
        let top = max(0, min(bounds.height - 1, offset.y * scale))
        // Original icons retain their bitmap dimensions instead of stretching
        // to a fixed 48px row. Missing art uses a readable text-button row.
        let sizes = buttons.map { button -> CGSize in
            guard let image = button.image else { return CGSize(width: 67, height: 40) }
            return CGSize(width: min(75, max(1, image.size.width)), height: min(128, max(1, image.size.height)))
        }
        let contentHeight = sizes.reduce(CGFloat(0)) { $0 + $1.height * scale }
        let backSize = back.hoverArt != nil ? (catalog.backButton?.size ?? CGSize(width: 67, height: 34)) : CGSize(width: 67, height: 34)
        let available = max(1, bounds.height - top - (back.isHidden ? 4 : backSize.height + 4) * scale)
        var scrollHeight = min(contentHeight, available)
        var backOrigin = CGPoint(x: 4 * scale, y: top + scrollHeight + 2 * scale)
        if !back.isHidden, original, let position = surround?.back,
           position.x >= 0, position.y >= 0,
           position.x * scale + backSize.width * scale <= bounds.width,
           position.y * scale + backSize.height * scale <= bounds.height {
            backOrigin = CGPoint(x: position.x * scale, y: position.y * scale)
            // Only shorten the scroll area when Back lies beneath the icons.
            if backOrigin.y >= top { scrollHeight = min(scrollHeight, max(1, backOrigin.y - top - 2 * scale)) }
        }
        scroll.frame = NSRect(x: x, y: top, width: max(1, bounds.width - x), height: max(1, scrollHeight))
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(scrollHeight, contentHeight))
        var y: CGFloat = 0
        for (button, size) in zip(buttons, sizes) {
            button.frame = NSRect(x: 0, y: y, width: min(document.bounds.width, size.width * scale), height: size.height * scale)
            y += size.height * scale
        }
        back.frame = NSRect(origin: backOrigin, size: NSSize(width: min(backSize.width * scale, bounds.width - backOrigin.x), height: backSize.height * scale))
        let artHeight = (surroundArt?.size.height ?? 0) * scale
        let controlsBottom = back.isHidden ? scroll.frame.maxY : max(scroll.frame.maxY, back.frame.maxY)
        visiblePanel = NSRect(x: 0, y: 0, width: bounds.width, height: min(bounds.height, max(artHeight, controlsBottom + 4 * scale)))
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden else { return nil }
        let local = convert(point, from: superview)
        guard visiblePanel.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let art = surroundArt {
            let scale = max(0.1, logicalScale)
            art.draw(in: NSRect(x: 0, y: 0, width: art.size.width * scale, height: art.size.height * scale),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedWhite: 0.08, alpha: 0.86).setFill()
            NSBezierPath(roundedRect: visiblePanel, xRadius: 5, yRadius: 5).fill()
        }
    }
}
#endif
