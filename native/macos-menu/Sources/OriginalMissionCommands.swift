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
    var onHover: (() -> Void)?
    private var hovered = false
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true; onHover?() }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func rightMouseDown(with event: NSEvent) {}
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
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
    private let help = NSTextField(wrappingLabelWithString: "")
    private let back = NSButton(title: "Back", target: nil, action: nil)
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
        help.textColor = .white
        help.font = .systemFont(ofSize: 10)
        help.alignment = .center
        addSubview(help)
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
                button.onHover = { [weak self] in
                    self?.help.stringValue = definition.title + "\n" + definition.detail
                }
                button.tag = index
                button.toolTip = definition.title + "\n" + definition.detail
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
            help.stringValue = page == .buildings ? "Hover a building for its original resource cost." : "Hover an icon for details."
            surround = catalog.surround(count: definitions.count, hasBack: page != .main)
            surroundArt = image(surround?.image)
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
        let scale = max(0.1, bounds.width / 90)
        heading.frame = NSRect(x: 2, y: 0, width: bounds.width - 4, height: 20 * scale)
        let offset = surround?.icons ?? CGPoint(x: 10, y: 25)
        let x = max(0, min(bounds.width - 40 * scale, offset.x * scale))
        let top = min(max(22 * scale, offset.y * scale), max(22 * scale, bounds.height - 160 * scale))
        let rowHeight = 48 * scale
        let helpHeight = 78 * scale
        help.frame = NSRect(x: 4 * scale, y: max(0, bounds.height - helpHeight), width: max(1, bounds.width - 8 * scale), height: helpHeight)
        let bottom = helpHeight + (back.isHidden ? 4 * scale : 42 * scale)
        scroll.frame = NSRect(x: x, y: top, width: max(1, bounds.width - x - 3 * scale), height: max(1, bounds.height - top - bottom))
        let total = max(scroll.contentSize.height, CGFloat(buttons.count) * rowHeight)
        document.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: total)
        // Flipped document coordinates keep the first original entry at the top.
        for (index, button) in buttons.enumerated() {
            button.frame = NSRect(x: 0, y: CGFloat(index) * rowHeight,
                                  width: document.bounds.width, height: rowHeight - 4 * scale)
        }
        // Reserve a separate Back row so long catalogs cannot cover it.
        back.frame = NSRect(x: 8 * scale, y: max(0, bounds.height - helpHeight - 38 * scale), width: bounds.width - 16 * scale, height: 34 * scale)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        if let art = surroundArt {
            let scale = bounds.width / 90
            art.draw(in: NSRect(x: 0, y: 0, width: art.size.width * scale, height: art.size.height * scale),
                     from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        } else {
            NSColor(calibratedWhite: 0.08, alpha: 0.86).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }
}
#endif
