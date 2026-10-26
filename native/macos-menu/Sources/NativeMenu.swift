#if os(macOS)
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Prototype view: places real WAD images and Lego.cfg menu items at the
/// original logical 640x480 coordinates. Font and overlays remain incomplete.

final class OriginalMenuCanvas: NSView {
    var resources: GameResources? { didSet { clearCache(); gameCursor = nil; needsDisplay = true } }
    var definitions: MenuDefinition? { didSet { menuIndex = 0; menuScroll.reset(); needsDisplay = true } }
    var missionSelection: MissionSelection? { didSet { missionHover = nil; needsDisplay = true } }
    var levelCatalog: LevelCatalog?
    var saveSlots: [OriginalSaveCatalog.Slot] = [] { didSet { needsDisplay = true } }
    var saveSlotLabel = "Save Game"
    var loadedSave: OriginalSaveFile? { didSet { needsDisplay = true } }
    var onNavigation: ((String) -> Void)?
    var onMissionSelected: ((MissionSelection.Node) -> Void)?
    var onQuitConfirmed: (() -> Void)?
    var onButtonActivated: (() -> Void)?
    var onMenuTransition: ((Int) -> Bool)?
    var transitionInProgress = false
    private var menuIndex = 0
    private var hoverIndex: Int?
    private var imageCache: [String: NSImage] = [:]
    private var fontCache: [String: OriginalBitmapFont] = [:]
    private var missingFonts = Set<String>()
    private var unavailable = Set<String>()
    private var hitRects: [(Int, CGRect)] = []
    private var missionRects: [(Int, CGRect)] = []
    private var saveRects: [(Int, CGRect)] = []
    private var missionHover: Int?
    private var saveHover: Int?
    private var history: [Int] = []
    private var menuScroll = OriginalMenuScroll()
    private var pointerY: Double?
    private var scrollTimer: Timer?
    private(set) var gameCursor: NSCursor? {
        didSet { if let window { window.invalidateCursorRects(for: self) } }
    }

    func configurePointer(config: LegoConfig) {
        gameCursor = resources.flatMap {
            OriginalMacCursor.load(config: config, resources: $0)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: gameCursor ?? .arrow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scrollTimer?.invalidate()
        scrollTimer = nil
        guard window != nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                           repeats: true) { [weak self] _ in
            self?.advanceMissionScroll()
        }
    }

    deinit { scrollTimer?.invalidate() }

    private func activeScrollableImageHeight() -> Double {
        guard let definitions, definitions.menus.indices.contains(menuIndex) else { return 0 }
        let menu = definitions.menus[menuIndex]
        guard menu.canScroll else { return 0 }
        let imagePath = menu.backgroundImage ?? menu.darkBackgroundImage
        return imagePath.flatMap { image($0)?.size.height }.map(Double.init) ?? 0
    }

    private func advanceMissionScroll() {
        guard !isHidden, let definitions,
              definitions.menus.indices.contains(menuIndex) else { return }
        let didMove = menuScroll.update(
            imageHeight: activeScrollableImageHeight(),
            canScroll: definitions.menus[menuIndex].canScroll,
            mouseY: pointerY, buttonsHeld: NSEvent.pressedMouseButtons != 0,
            elapsed: 1.0 / 30.0)
        if didMove { needsDisplay = true }
    }


    func navigateDirectly(to next: Int) {
        guard let definitions, definitions.menus.indices.contains(next) else { return }
        history.append(menuIndex)
        menuIndex = next
        menuScroll.reset()
        hoverIndex = nil
        missionHover = nil
        saveHover = nil
        needsDisplay = true
        onNavigation?("Original menu: \(definitions.menus[next].internalName)")
    }

    /// Present the original ARE YOU SURE menu and its configured Yes/No
    /// images and fonts, rather than a separate native popup.
    @discardableResult
    func showOriginalQuitConfirmation() -> Bool {
        guard let definitions,
              let index = definitions.quitConfirmationIndex,
              definitions.menus.indices.contains(index) else { return false }
        if menuIndex != index {
            history.append(menuIndex)
            menuIndex = index
            menuScroll.reset()
            hoverIndex = nil
            missionHover = nil
            saveHover = nil
        }
        needsDisplay = true
        onNavigation?("Original menu: \(definitions.menus[index].internalName)")
        window?.makeFirstResponder(self)
        return true
    }

    private var currentMissions: [MissionSelection.Node] {
        guard let missionSelection else { return [] }
        if menuIndex == 1 { return missionSelection.missions }
        if menuIndex == 2 { return missionSelection.tutorials }
        return []
    }

    private func missionAvailable(_ entry: MissionSelection.Node,
                                  in nodes: [MissionSelection.Node]) -> Bool {
        if menuIndex == 2 { return true } // All retail tutorials start unlocked.
        guard let loadedSave, let levelCatalog else { return entry.initiallyAvailable }

        let completed = Set(levelCatalog.missions.enumerated().compactMap { index, level in
            loadedSave.completedLevelIndices.contains(index) ? level.identifier.lowercased() : nil
        })
        let key = entry.identifier.lowercased()
        if entry.initiallyAvailable || completed.contains(key) { return true }
        // Front_Levels_UpdateAvailable propagates availability only along
        // links from levels marked completed in the loaded save.
        return nodes.contains { parent in
            completed.contains(parent.identifier.lowercased()) &&
            parent.nextIdentifiers.contains { $0.lowercased() == key }
        }
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private func clearCache() {
        imageCache.removeAll()
        fontCache.removeAll()
        missingFonts.removeAll()
        unavailable.removeAll()
        history.removeAll()
        menuScroll.reset()
        pointerY = nil
        hoverIndex = nil
        missionHover = nil
        saveHover = nil
        hitRects.removeAll()
        missionRects.removeAll()
        saveRects.removeAll()
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
        bounds.fill()
        guard resources != nil, let ctx = NSGraphicsContext.current else { return }
        ctx.saveGraphicsState()
        defer { ctx.restoreGraphicsState() }
        ctx.cgContext.scaleBy(x: bounds.width / 640.0, y: bounds.height / 480.0)
        ctx.cgContext.interpolationQuality = .none
        hitRects.removeAll()
        missionRects.removeAll()
        saveRects.removeAll()

        let backgroundName = "Interface/FrontEnd/MenuBGpic.bmp"
        if let background = image(backgroundName) {
            drawImage(background, at: CGRect(origin: .zero, size: background.size))
        }
        guard let definitions, definitions.menus.indices.contains(menuIndex) else { return }
        let menu = definitions.menus[menuIndex]
        if let source = menu.backgroundImage, let img = image(source) {
            let frame = imageFrame(for: source,
                                   fallback: CGRect(origin: .zero, size: img.size))
            drawImage(img, at: frame.offsetBy(
                dx: 0, dy: menu.canScroll ? menuScroll.offsetY : 0))
        }
        // Show only known BMP overlays. Original FLIC/AVI/LWS animations must be
        // handled by dedicated decoders, not by inventing placeholder animations.
        for overlay in menu.overlays where overlay.asset.lowercased().hasSuffix(".bmp") {
            if let art = image(overlay.asset) {
                drawImage(art, at: CGRect(x: CGFloat(overlay.x), y: CGFloat(overlay.y),
                                          width: art.size.width, height: art.size.height))
            }
        }

        // Front_Menu_Update centers FullName at the screen midpoint and
        // places it at menu.position.y + menu.anchoredPosition.y.
        if menu.displayTitle && !menu.internalName.isEmpty {
            drawText(menu.internalName, x: 320, y: CGFloat(menu.y + menu.titleAnchorY),
                     size: 23, hovered: false, enabled: false,
                     centered: true, fontPath: menu.titleFont)
        }

        for (i, item) in menu.items.enumerated() {
            let x = CGFloat(menu.x + item.x)
            let y = CGFloat(menu.y + item.y)
            let hovered = hoverIndex == i
            let actionable = (item.kind == .next && item.linkedMenu != nil) ||
                             item.kind == .trigger
            let assetPath = hovered ? (item.imageHover ?? item.imageNormal) : item.imageNormal
            if let assetPath, let artwork = image(assetPath) {
                // Mirror Front_MenuItem_CreateImageItem centerOffLo/Hi.
                let drawnX = menu.autoCenter ? x - artwork.size.width / 2 : x
                let rect = CGRect(x: drawnX, y: y, width: artwork.size.width,
                                  height: artwork.size.height)
                drawImage(artwork, at: rect)
                if actionable { hitRects.append((i, rect)) }
            } else if !item.caption.isEmpty {
                let measured = drawText(item.caption, x: x, y: y, size: 22,
                                        hovered: hovered, enabled: actionable, centered: menu.autoCenter,
                                        fontPath: hovered ? menu.hoverFont : menu.normalFont)
                if actionable { hitRects.append((i, measured)) }
            }
        }

        // MainMenuFull::Menu2 / Menu3 contain their Select items at runtime,
        // created by MainMenuFull_AddMissionsDisplay, not by Lego.cfg ItemN.
        // Draw their original MenuBMP variants using LevelLinks DFS order.
        // Front_MenuItem_DrawSelectItem: 0=light, 1=dark, 2=locked.
        let entries = currentMissions
        for (index, entry) in entries.enumerated() {
            guard entry.imagePaths.count == 3 else { continue }
            let available = missionAvailable(entry, in: entries)
            let isHovered = missionHover == index && available
            let imageNumber = !available ? 2 : (isHovered ? 0 : 1)
            guard let artwork = image(entry.imagePaths[imageNumber]) else { continue }
            let x = CGFloat(menu.x + entry.x) -
                    (menu.autoCenter ? artwork.size.width / 2 : 0)
            let y = CGFloat(menu.y + entry.y) +
                    CGFloat(menu.canScroll ? menuScroll.offsetY : 0)
            let frame = CGRect(x: x, y: y, width: artwork.size.width,
                               height: artwork.size.height)
            drawImage(artwork, at: frame)
            if available { missionRects.append((index, frame)) }
        }
        // Like Front_Callback_SelectMissionItem, display the real localized
        // mission name when the cursor hovers an unlocked wormhole icon.
        if let missionHover, entries.indices.contains(missionHover) {
            drawText(entries[missionHover].title, x: 320, y: 390, size: 22,
                     hovered: false, enabled: true, centered: true,
                     fontPath: menu.titleFont)
        }

        // The original game creates the Load_A_Saved_Game menu's five Select
        // items dynamically (Front_LoadLevels) with offsets -200:-100 and a
        // 60px step. Only show statuses read from the actual original files.
        if menuIndex == 3 {
            for (index, slot) in saveSlots.enumerated() {
                let label = "\(saveSlotLabel) \(slot.number)"
                let valid: Bool
                switch slot.state {
                case .valid: valid = true
                default: valid = false
                }
                let hit = drawText(label, x: CGFloat(menu.x - 200),
                                   y: CGFloat(menu.y - 100 + index * 60),
                                   size: 20, hovered: saveHover == index,
                                   enabled: valid, centered: false,
                                   fontPath: saveHover == index ? menu.hoverFont : menu.normalFont)
                if valid { saveRects.append((index, hit)) }
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
                                      options: [.mouseMoved, .mouseEnteredAndExited,
                                                .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }

    private func logicalPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x * 640.0 / bounds.width, y: p.y * 480.0 / bounds.height)
    }

    private func updateHover(at pos: CGPoint) {
        let newHover = hitRects.first(where: { $0.1.contains(pos) })?.0
        let newMissionHover = missionRects.first(where: { $0.1.contains(pos) })?.0
        let newSaveHover = saveRects.first(where: { $0.1.contains(pos) })?.0
        if hoverIndex != newHover || missionHover != newMissionHover ||
           saveHover != newSaveHover {
            hoverIndex = newHover
            missionHover = newMissionHover
            saveHover = newSaveHover
            needsDisplay = true
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let pos = logicalPoint(event)
        pointerY = Double(pos.y)
        updateHover(at: pos)
    }

    override func mouseEntered(with event: NSEvent) {
        let pos = logicalPoint(event)
        pointerY = Double(pos.y)
        updateHover(at: pos)
    }

    override func mouseExited(with event: NSEvent) {
        pointerY = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard let definitions, definitions.menus.indices.contains(menuIndex) else {
            return super.scrollWheel(with: event)
        }
        let screen = definitions.menus[menuIndex]
        if menuScroll.wheel(deltaY: Double(event.scrollingDeltaY),
                            imageHeight: activeScrollableImageHeight(),
                            canScroll: screen.canScroll) {
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !transitionInProgress else { return }
        let pos = logicalPoint(event)
        if let index = saveRects.first(where: { $0.1.contains(pos) })?.0,
           saveSlots.indices.contains(index) {
            if case .valid(let save) = saveSlots[index].state {
                onButtonActivated?()
                loadedSave = save
                history.append(menuIndex)
                menuIndex = 1 // OpenLRR loads save then enters mission map.
                menuScroll.reset()
                saveHover = nil
                missionHover = nil
                needsDisplay = true
                onNavigation?("Loaded original save slot \(saveSlots[index].number) (read-only)")
                return
            }
        }
        if let index = missionRects.first(where: { $0.1.contains(pos) })?.0,
           currentMissions.indices.contains(index) {
            onButtonActivated?()
            // Route the original mission identifier into the native world
            // loader, without modifying saves or pretending to run objectives.
            onMissionSelected?(currentMissions[index])
            return
        }
        guard let index = hitRects.first(where: { $0.1.contains(pos) })?.0,
              let menus = definitions?.menus, menus.indices.contains(menuIndex),
              menus[menuIndex].items.indices.contains(index) else { return }
        let selected = menus[menuIndex].items[index]
        if selected.kind == .next || selected.kind == .trigger {
            onButtonActivated?()
        }
        if selected.kind == .next, let next = selected.linkedMenu,
           menus.indices.contains(next) {
            // Original LWSC Boulder transition; fall back to instant if the
            // user's WAD contains no usable mesh/scene combination.
            if onMenuTransition?(next) != true { navigateDirectly(to: next) }
        } else if selected.kind == .trigger {
            // In the MainMenuFull confirmation screen the terminal trigger
            // is bound to triggerQuitApp in the retail Front_LoadMenuSet.
            if menuIndex == definitions?.quitConfirmationIndex && selected.endsMenu {
                onQuitConfirmed?()
            } else {
                onNavigation?("Original menu trigger not yet implemented: \(selected.caption)")
            }
        }
        // Cycle / Select / Slider operations remain separate subsystems.
    }

    override func keyDown(with event: NSEvent) {
        guard !transitionInProgress else { return }
        if event.keyCode == 53, let previous = history.popLast() {
            menuIndex = previous
            menuScroll.reset()
            hoverIndex = nil
            missionHover = nil
            saveHover = nil
            needsDisplay = true
            return
        }
        super.keyDown(with: event)
    }
}

/// Keeps the game's 640x480 canvas at a true 4:3 aspect ratio and reserves
/// separate space for prototype-only controls. The game never draws beneath
/// the toolbar, even when the window is resized.
private final class NativeMenuHostView: NSView {
    weak var gameCanvas: NSView?
    weak var missionView: NSView?
    weak var rockWipeView: NSView?
    weak var controlBar: NSView?
    private let controlHeight: CGFloat = 80

    override func layout() {
        super.layout()
        controlBar?.frame = NSRect(x: 0, y: 0,
                                   width: bounds.width, height: controlHeight)
        let availableHeight = max(0, bounds.height - controlHeight)
        let scale = min(bounds.width / 640.0, availableHeight / 480.0)
        let width = 640.0 * scale
        let height = 480.0 * scale
        gameCanvas?.frame = NSRect(x: (bounds.width - width) / 2,
                                   y: controlHeight + (availableHeight - height) / 2,
                                   width: width, height: height)
        missionView?.frame = NSRect(x: 0, y: controlHeight,
                                    width: bounds.width, height: availableHeight)
        if let gameCanvas { rockWipeView?.frame = gameCanvas.frame }
    }
}

/// Creates a real native ARM64 AppKit window and reads only the selected WADs.
final class NativeMenuApplication: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var root: NativeMenuHostView!
    private var canvas: OriginalMenuCanvas!
    private var missionView: NativeMissionWorkspace?
    private var savedMenuWindowFrame: NSRect?
    private var toolbarButtons: NSStackView!
    private var backToMenuButton: NSButton!
    private var missionMusicButton: NSButton!
    private var missionMusicToggle: NSButton!
    private var status: NSTextField!
    private let originalAudio = OriginalMenuAudio()
    private let missionAudio = OriginalMissionAudio()
    private let buttonAudio = OriginalMenuButtonAudio()
    private let rockWipeAudio = OriginalMenuButtonAudio()
    private let selectedWadDefaultsKey = "OriginalGameWadURL.v1"
    private let audioFolderDefaultsKey = "OriginalGameAudioFolderURL.v1"
    private var activeWadURL: URL?
    private var activeResources: GameResources?
    private var activeConfig: LegoConfig?
    private var approvedQuit = false

    private var selectedAudioFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: audioFolderDefaultsKey),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 680),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Rock Raiders — Native Mac Prototype"
        window.center()
        window.minSize = NSSize(width: 640, height: 560)
        window.acceptsMouseMovedEvents = true
        window.delegate = self
        root = NativeMenuHostView(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.black.cgColor
        window.contentView = root

        canvas = OriginalMenuCanvas(frame: NSRect(x: 0, y: 80, width: 800, height: 600))
        root.gameCanvas = canvas
        // Keep persistent audio diagnostics visible while navigating menus.
        canvas.onNavigation = { [weak self] value in
            self?.window.title = "Rock Raiders — \(value)"
        }
        canvas.onMissionSelected = { [weak self] node in
            self?.openLevel(identifier: node.identifier)
        }
        canvas.onQuitConfirmed = { [weak self] in
            guard let self else { return }
            self.approvedQuit = true
            NSApp.terminate(nil)
        }
        canvas.onMenuTransition = { [weak self] next in
            self?.playOriginalRockWipe(to: next) ?? false
        }
        canvas.onButtonActivated = { [weak self] in
            self?.buttonAudio.play()
        }
        root.addSubview(canvas)

        let toolbar = NSVisualEffectView(frame: CGRect(x: 0, y: 0, width: 800, height: 80))
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        root.controlBar = toolbar
        root.addSubview(toolbar)

        let open = NSButton(title: "Open original WAD files…", target: self,
                            action: #selector(openArchive))
        let locateSounds = NSButton(title: "Locate Sounds…", target: self,
                                    action: #selector(chooseOriginalSoundsFolder))
        locateSounds.toolTip = "Select an original Data, Sounds or Streamed folder (only if audio is missing)."
        let preview = NSButton(title: "First Level", target: self,
                               action: #selector(openFirstOriginalLevel))
        preview.toolTip = "Open the first original mission terrain with camera and tile inspection."
        let about = NSButton(title: "About", target: self, action: #selector(aboutPrototype))
        let quit = NSButton(title: "Quit", target: NSApp,
                            action: #selector(NSApplication.terminate(_:)))
        let music = NSButton(title: "Mission Music…", target: self,
                             action: #selector(chooseMissionMusic))
        music.toolTip = "Select your original CD soundtrack audio files for missions."
        let buttons = NSStackView(views: [preview, open, music, locateSounds, about, quit])
        toolbarButtons = buttons
        backToMenuButton = NSButton(title: "← Back to Main Menu",
                                    target: self, action: #selector(backToMenu))
        backToMenuButton.toolTip = "Return to the original menu in this window."
        backToMenuButton.isHidden = true
        backToMenuButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(backToMenuButton)
        missionMusicButton = NSButton(title: "Mission Music…", target: self, action: #selector(chooseMissionMusic))
        missionMusicToggle = NSButton(checkboxWithTitle: "Music", target: self, action: #selector(toggleMissionMusic))
        missionMusicToggle.state = missionAudio.enabled ? .on : .off
        for control in [missionMusicButton!, missionMusicToggle!] {
            control.isHidden = true
            control.translatesAutoresizingMaskIntoConstraints = false
            toolbar.addSubview(control)
        }
        missionAudio.onStatus = { [weak self] message in
            self?.status.stringValue = message
            self?.status.toolTip = message
        }
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
            backToMenuButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            backToMenuButton.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 9),
            missionMusicButton.leadingAnchor.constraint(equalTo: backToMenuButton.trailingAnchor, constant: 16),
            missionMusicButton.centerYAnchor.constraint(equalTo: backToMenuButton.centerYAnchor),
            missionMusicToggle.leadingAnchor.constraint(equalTo: missionMusicButton.trailingAnchor, constant: 16),
            missionMusicToggle.centerYAnchor.constraint(equalTo: backToMenuButton.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(lessThanOrEqualTo: toolbar.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 7)
        ])
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.count > 1 {
            load(URL(fileURLWithPath: CommandLine.arguments[1]))
        } else if let savedPath = UserDefaults.standard.string(forKey: selectedWadDefaultsKey),
                  !savedPath.isEmpty {
            load(URL(fileURLWithPath: savedPath), automatic: true)
        }
    }

    // Route Cmd-Q, toolbar Quit and the window's red close button through
    // the original menu. Only the configured Yes trigger permits termination.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if approvedQuit { return .terminateNow }
        if missionView != nil { returnToMainMenu() }
        if canvas?.showOriginalQuitConfirmation() == true { return .terminateCancel }

        // Assets/CFG not available: never quit without affirmative consent.
        let confirmation = NSAlert()
        confirmation.messageText = "Quit LEGO Rock Raiders?"
        confirmation.informativeText = "Are you sure you want to quit the game?"
        confirmation.alertStyle = .warning
        confirmation.addButton(withTitle: "No")
        confirmation.addButton(withTitle: "Yes")
        return confirmation.runModal() == .alertSecondButtonReturn
            ? .terminateNow : .terminateCancel
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    private func playOriginalRockWipe(to next: Int) -> Bool {
        guard root.rockWipeView == nil,
              let activeConfig, let activeResources,
              let wipe = NativeRockWipeView(frame: canvas.frame,
                                           config: activeConfig,
                                           resources: activeResources) else { return false }
        canvas.transitionInProgress = true
        if let wad = activeWadURL {
            rockWipeAudio.configure(config: activeConfig, resources: activeResources,
                beside: wad, extraAudioRoot: selectedAudioFolder, sampleName: "SFX_RockWipe")
            rockWipeAudio.play()
        }
        root.rockWipeView = wipe
        root.addSubview(wipe, positioned: .above, relativeTo: canvas)
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        wipe.play(midpoint: { [weak self] in
            self?.canvas.navigateDirectly(to: next)
        }, completed: { [weak self, weak wipe] in
            wipe?.removeFromSuperview()
            self?.root.rockWipeView = nil
            self?.canvas.transitionInProgress = false
            self?.rockWipeAudio.stop()
            if let self { self.window.makeFirstResponder(self.canvas) }
        })
        return true
    }

    @objc private func openFirstOriginalLevel() {
        guard let config = activeConfig,
              let identifier = config.valueUnderGame(["Main", "StartLevel"]),
              !identifier.isEmpty else {
            presentLevelError("The original mission catalog is unavailable. Confirm the installed LegoRR0/1.wad pair contains Lego.cfg.")
            return
        }
        openLevel(identifier: identifier)
    }

    private func openLevel(identifier: String) {
        guard let resources = activeResources, let config = activeConfig else {
            presentLevelError("Load the original game archives before opening a mission.")
            return
        }
        do {
            let manifest = try LevelRuntimeResources(config: config, identifier: identifier)
            let world = try LevelWorld(manifest: manifest, resources: resources)
            let placements = try? OriginalObjectList(manifest: manifest, resources: resources)
            // Decode the authentic retail .npl from the user's WAD. No
            // substitute tutorial content or fabricated missing functions.
            let script = try? NERPsScript.load(levelIdentifier: identifier,
                                                config: config, resources: resources)
            // Decode text-only tutorial messages from the configured
            // NERPMessageFile, without exporting or modifying WAD contents.
            let missionMessages: NativeNERPsMessageFile?
            if let path = manifest.scriptMessagePath {
                missionMessages = try? NativeNERPsMessageFile(
                    data: resources.data(at: path, maximumBytes: 1_000_000))
            } else {
                missionMessages = nil
            }
            let missionNERPs = script.map {
                NativeNERPsGameState(script: $0, messages: missionMessages)
            }

            // Mission selection changes the scene in the existing window, as
            // the retail game does. Never spawn another NSWindow per mission.
            let viewer = try NativeMissionWorkspace(
                frame: root.bounds, world: world, objects: placements,
                resources: resources, textureSet: manifest.textureSetSetting,
                nerpsState: missionNERPs, config: config,
                blockSize: Double(config.valueUnderGame(identifier.components(separatedBy: "::") + ["BlockSize"]) ?? "40") ?? 40,
                wadURL: activeWadURL, extraAudioRoot: selectedAudioFolder)
            viewer.originalCursor = canvas.gameCursor
            viewer.onBack = { [weak self] in self?.returnToMainMenu() }
            missionView?.removeFromSuperview()
            missionView = viewer
            originalAudio.stop()
            buttonAudio.stop()
            let musicStatus = activeWadURL.map {
                missionAudio.start(config: config, beside: $0, extraRoot: selectedAudioFolder)
            } ?? "Mission soundtrack unavailable"
            root.missionView = viewer
            root.addSubview(viewer, positioned: .above, relativeTo: canvas)
            canvas.isHidden = true
            toolbarButtons.isHidden = true
            backToMenuButton.isHidden = false
            missionMusicButton.isHidden = false
            missionMusicToggle.isHidden = false

            if savedMenuWindowFrame == nil {
                savedMenuWindowFrame = window.frame
                let current = window.contentView?.bounds.size ?? .zero
                let preferred = NSSize(width: max(current.width, 960),
                                       height: max(current.height, 760))
                if preferred != current {
                    window.setContentSize(preferred)
                    window.center()
                }
            }
            root.needsLayout = true
            root.layoutSubtreeIfNeeded()
            window.title = "Rock Raiders — \(world.title)"
            viewer.focusActiveView()
            window.makeKeyAndOrderFront(nil)
            status.stringValue = "\(world.title) • \(world.width)×\(world.height) blocks • \(placements?.rockRaiders.count ?? 0) Rock Raiders"
            status.stringValue += " • \(musicStatus)"
            if missionAudio.enabled && !musicStatus.hasPrefix("Playing ") {
                let alert = NSAlert()
                alert.messageText = "Mission soundtrack could not start"
                alert.informativeText = musicStatus
                alert.addButton(withTitle: "Choose music files…")
                alert.addButton(withTitle: "Continue")
                alert.beginSheetModal(for: window) { [weak self] result in
                    if result == .alertFirstButtonReturn { self?.chooseMissionMusic() }
                }
            }
            status.toolTip = status.stringValue
        } catch {
            presentLevelError("\(identifier): \(error)")
        }
    }

    @objc private func backToMenu() {
        returnToMainMenu()
    }

    private func returnToMainMenu() {
        missionAudio.stop()
        missionView?.removeFromSuperview()
        missionView = nil
        root.missionView = nil
        canvas.isHidden = false
        toolbarButtons.isHidden = false
        backToMenuButton.isHidden = true
        missionMusicButton.isHidden = true
        missionMusicToggle.isHidden = true
        if let saved = savedMenuWindowFrame {
            window.setFrame(saved, display: true, animate: false)
            savedMenuWindowFrame = nil
        }
        window.title = "Rock Raiders — Original Menu"
        root.needsLayout = true
        root.layoutSubtreeIfNeeded()
        window.makeFirstResponder(canvas)
        restartOriginalAudio()
        status.toolTip = status.stringValue
    }

    private func presentLevelError(_ message: String) {
        status.stringValue = "Unable to open original mission: \(message)"
        status.toolTip = status.stringValue
        let alert = NSAlert()
        alert.messageText = "Original mission could not be loaded"
        alert.informativeText = message + "\n\nNo original game or save files were changed."
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
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

    @objc private func openOriginalAudioResource() {
        // RRU requires the user to review and agree to its download terms.
        // Never automatically download or redistribute the original tracks.
        if let page = URL(string: "https://rockraidersunited.com/files/lego_rock_raiders/resources/atmosdel-and-statswav-r323/") {
            NSWorkspace.shared.open(page)
        }
    }

    @objc private func chooseOriginalSoundsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Select your original Data, Sounds or Streamed directory (or a folder containing the RRU Atmosdel.wav). Nothing is changed or uploaded."
        if let folder = selectedAudioFolder { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let folder = panel.url, let self else { return }
            UserDefaults.standard.set(folder.path, forKey: self.audioFolderDefaultsKey)
            self.restartOriginalAudio()
        }
    }

    @objc private func toggleMissionMusic() {
        missionAudio.enabled = missionMusicToggle.state == .on
        restartMissionMusic()
    }

    private func restartMissionMusic() {
        guard missionView != nil, let config = activeConfig, let wad = activeWadURL else { return }
        status.stringValue = missionAudio.start(config: config, beside: wad, extraRoot: selectedAudioFolder)
        status.toolTip = status.stringValue
    }

    @objc private func chooseMissionMusic() {
        let panel = NSOpenPanel()
        panel.title = "Select original Rock Raiders soundtrack tracks"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ["wav", "mp3", "m4a", "aiff", "aif"].compactMap { UTType(filenameExtension: $0) }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            self.missionAudio.setTracks(panel.urls)
            self.missionAudio.enabled = true
            self.missionMusicToggle.state = .on
            self.status.stringValue = "Original soundtrack selected for missions"
            self.restartMissionMusic()
        }
    }

    private func restartOriginalAudio() {
        guard missionView == nil, let activeWadURL, let activeResources, let activeConfig else { return }
        let result = originalAudio.start(config: activeConfig,
                                         resources: activeResources,
                                         beside: activeWadURL,
                                         additionalAudioRoot: selectedAudioFolder)
        status.stringValue = result
        status.toolTip = result
    }

    private func load(_ url: URL, automatic: Bool = false) {
        missionAudio.stop()
        originalAudio.stop()
        buttonAudio.stop()
        activeWadURL = nil
        activeResources = nil
        activeConfig = nil
        do {
            let resources = try GameResources(selectedWadURL: url)
            guard resources.exists("Interface/FrontEnd/MenuBGpic.bmp") else {
                throw GameResources.ResourceError.missingAsset("Interface/FrontEnd/MenuBGpic.bmp")
            }
            canvas.resources = resources
            if resources.exists("Lego.cfg") {
                let config = try LegoConfig(data: resources.configData())
                canvas.definitions = try MenuDefinition(config: config)
                canvas.configurePointer(config: config)
                // Source-grounded mission maps using the game's NextLevel
                // order and LevelLinks, no handwritten mission assets.
                if let catalog = try? LevelCatalog(config: config) {
                    canvas.levelCatalog = catalog
                    canvas.missionSelection = MissionSelection(config: config, catalog: catalog)
                    let roots = OriginalAudioFileLocator.automaticAudioRoots(
                        home: FileManager.default.homeDirectoryForCurrentUser)
                    canvas.saveSlots = OriginalSaveCatalog(
                        selectedWadURL: url,
                        expectedMissionCount: canvas.missionSelection?.missions.count ?? 0,
                        additionalInstallRoots: roots).slots
                    canvas.saveSlotLabel = (config.valueUnderGame(["Menu", "Save_Game"]) ??
                        "Save_Game").replacingOccurrences(of: "_", with: " ")
                } else {
                    canvas.levelCatalog = nil
                    canvas.missionSelection = nil
                    canvas.saveSlots = []
                }
                canvas.loadedSave = nil
                activeWadURL = url
                activeResources = resources
                activeConfig = config
                restartOriginalAudio()
                buttonAudio.configure(config: config, resources: resources,
                                      beside: url, extraAudioRoot: selectedAudioFolder)
            } else {
                canvas.definitions = nil
                status.stringValue = "Original background loaded. LegoRR1.wad with Lego.cfg is needed for navigation."
            }
            // Persist only successfully loaded original archives. The app is
            // not sandboxed; this is the user-selected local path, not a copy.
            UserDefaults.standard.set(url.path, forKey: selectedWadDefaultsKey)
            window.title = "Rock Raiders — Original Asset Native Prototype"
        } catch {
            canvas.resources = nil
            canvas.definitions = nil
            canvas.missionSelection = nil
            canvas.levelCatalog = nil
            canvas.loadedSave = nil
            canvas.saveSlots = []
            if automatic {
                UserDefaults.standard.removeObject(forKey: selectedWadDefaultsKey)
                status.stringValue = "Previous WAD location unavailable; select the original WAD again."
                return
            }
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
        alert.informativeText = "Reads your original WADs and Lego.cfg without modifying them. The 3D terrain preview uses original MAP geometry with diagnostic materials, but units, drilling, textures and objectives are not yet ported. Original saves are read-only."
        alert.beginSheetModal(for: window)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // When someone downloads/extracts the RRU audio and comes back to
        // the app, silently retry discovery; never interrupt playing audio.
        if missionView == nil && !originalAudio.isPlaying { restartOriginalAudio() }
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
