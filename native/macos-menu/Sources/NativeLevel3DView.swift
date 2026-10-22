#if os(macOS)
import AppKit
import ImageIO
import SceneKit

/// Native Apple Silicon 3D inspection of real retail MAP terrain.
/// SceneKit is the first rendering bridge while the original renderer,
/// textures, objects and gameplay logic are being ported. The meshes are
/// derived exclusively from the user's original files.
final class NativeLevel3DView: SCNView {
    let world: LevelWorld
    let terrainMesh: NativeTerrainMesh
    let originalObjects: OriginalObjectList?
    let textureSummary: String
    var onExit: (() -> Void)?
    private let navigation: NativeLevelNavigation
    private var raiderMarkers: [String: SCNNode] = [:]
    private var selectedRaider: String?
    var onTileSelected: ((LevelWorld.Tile) -> Void)?
    var originalCursor: NSCursor? {
        didSet { if let window { window.invalidateCursorRects(for: self) } }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: originalCursor ?? .arrow)
    }
    var onInteractionMessage: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, world: LevelWorld, objects: OriginalObjectList?,
         resources: GameResources, textureSet: String?) throws {
        self.world = world
        self.terrainMesh = try NativeTerrainMesh(world: world)
        self.originalObjects = objects
        self.navigation = NativeLevelNavigation(world: world)

        let textureCatalog = OriginalTerrainTextureCatalog(
            textureSetSetting: textureSet, resources: resources)
        var imageCache: [UInt8: NSImage] = [:]
        func originalBitmap(_ id: UInt8) -> NSImage? {
            if let cached = imageCache[id] { return cached }
            guard let bytes = textureCatalog?.bytes(for: id, resources: resources),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let bitmap = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  bitmap.width > 0, bitmap.height > 0 else { return nil }
            let result = NSImage(cgImage: bitmap,
                                 size: CGSize(width: bitmap.width, height: bitmap.height))
            imageCache[id] = result
            return result
        }
        // Validate a genuine ground texture before declaring the world textured.
        let groundTexture = originalBitmap(0)
        self.textureSummary = groundTexture == nil ?
            "Original terrain texture not found; showing diagnostic materials" :
            "Original \(textureCatalog?.family.rawValue ?? "world") BMP terrain textures"

        super.init(frame: frame, options: nil)
        backgroundColor = NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.09, alpha: 1)
        autoenablesDefaultLighting = true
        allowsCameraControl = true
        preferredFramesPerSecond = 60
        rendersContinuously = false

        let scene = SCNScene()
        scene.background.contents = backgroundColor
        scene.fogColor = NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.09, alpha: 1)
        scene.fogStartDistance = 18
        scene.fogEndDistance = 48

        for surface in terrainMesh.surfaces {
            // A few material-grouped triangle meshes replace thousands of
            // SCNNode cubes, allowing normal level sizes to stay responsive.
            let vertices: [SCNVector3] = surface.vertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            }
            let normals: [SCNVector3] = surface.normals.map {
                SCNVector3($0.x, $0.y, $0.z)
            }
            guard vertices.count <= Int(UInt32.max) else { continue }
            let indices = (0..<vertices.count).map { UInt32($0) }
            // UVs repeat original wall/ground bitmaps once per tile. For
            // vertical walls use their horizontal axis and height rather
            // than projecting the same flat color over the entire level.
            let uv: [CGPoint] = zip(surface.vertices, surface.normals).map { pair in
                let p = pair.0
                let n = pair.1
                if abs(n.y) >= 0.5 {
                    return CGPoint(x: CGFloat(p.x), y: CGFloat(p.z))
                }
                let horizontal = abs(n.x) > abs(n.z) ? p.z : p.x
                return CGPoint(x: CGFloat(horizontal),
                               y: CGFloat(p.y) / CGFloat(NativeTerrainMesh.previewWallHeight))
            }
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices),
                          SCNGeometrySource(normals: normals),
                          SCNGeometrySource(textureCoordinates: uv)],
                elements: [SCNGeometryElement(indices: indices,
                                              primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = Self.color(surface.material)
            if textureCatalog != nil,
               let id = Self.textureID(for: surface.material),
               let image = originalBitmap(id) ?? groundTexture {
                material.diffuse.contents = image
                material.diffuse.wrapS = .repeat
                material.diffuse.wrapT = .repeat
                material.diffuse.magnificationFilter = .linear
                material.diffuse.minificationFilter = .linear
            }
            material.lightingModel = .blinn
            material.isDoubleSided = true
            material.specular.contents = NSColor(calibratedWhite: 0.14, alpha: 1)
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = "Retail MAP / \(surface.material.rawValue)"
            scene.rootNode.addChildNode(node)
        }

        // The original TVCamera placement overrides the first exposed-cavern
        // fallback. Its heading will be used when original camera semantics
        // are fully reproduced; do not invent a matching retail viewing angle.
        let start = world.initialCameraTile
        let cameraX = objects?.initialCamera?.x ?? Double(start.x) + 0.5
        let cameraZ = objects?.initialCamera?.y ?? Double(start.y) + 0.5
        let centerX = Float(cameraX) - Float(world.width) / 2
        let centerZ = Float(cameraZ) - Float(world.height) / 2
        let centerY = (world.elevation(atX: cameraX, y: cameraZ) ?? 0)
                      * NativeTerrainMesh.previewHeightScale
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = max(400, Double(max(world.width, world.height) * 3))
        camera.camera?.fieldOfView = 60
        camera.position = SCNVector3(centerX,
                                     centerY + 10,
                                     centerZ + 12)
        camera.look(at: SCNVector3(centerX, centerY, centerZ))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedWhite: 0.40, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        // Debug proxies mark REAL retail OL placements: no fabricated Raider
        // or building spawns, and no claim of original LightWave models.
        if let objects {
            for placement in objects.placements where !placement.isCamera {
                guard placement.x >= 0, placement.y >= 0,
                      placement.x < Double(world.width),
                      placement.y < Double(world.height),
                      let tile = world.tile(x: Int(placement.x), y: Int(placement.y)),
                      tile.excavation.isDiscoveredCavern else { continue }
                let geometry: SCNGeometry = placement.isRockRaider ?
                    SCNCapsule(capRadius: 0.22, height: 0.80) :
                    SCNSphere(radius: 0.24)
                let material = SCNMaterial()
                material.diffuse.contents = placement.isRockRaider ?
                    NSColor.systemYellow : NSColor.systemTeal
                material.lightingModel = .blinn
                geometry.materials = [material]
                let marker = SCNNode(geometry: geometry)
                marker.name = "Original OL: \(placement.identifier) / \(placement.type)"
                marker.position = worldPosition(x: placement.x, z: placement.y)
                scene.rootNode.addChildNode(marker)
                if placement.isRockRaider {
                    raiderMarkers[placement.identifier] = marker
                }
            }
        }

        self.scene = scene
        self.pointOfView = camera
    }

    required init?(coder: NSCoder) { nil }

    /// These are the original SurfaceTexture identifiers, not arbitrary
    /// diagnostic colors (src/openlrr/game/GameCommon.h). Transition variants
    /// and wall orientation are still under development.
    private static func textureID(for material: NativeTerrainMesh.Material) -> UInt8? {
        switch material {
        case .cavernFloor: return 0x00
        case .dirt, .wallFace: return 0x02
        case .mediumRock: return 0x03
        case .hardRock: return 0x04
        case .immovable, .hidden: return 0x05
        case .crystal: return 0x20
        case .ore: return 0x40
        case .water: return 0x45
        case .lava: return 0x46
        case .recharge: return 0x67
        }
    }

    private static func color(_ material: NativeTerrainMesh.Material) -> NSColor {
        switch material {
        case .cavernFloor: return NSColor(calibratedRed: 0.30, green: 0.39, blue: 0.35, alpha: 1)
        case .hardRock: return NSColor(calibratedRed: 0.46, green: 0.48, blue: 0.53, alpha: 1)
        case .mediumRock: return NSColor(calibratedRed: 0.60, green: 0.47, blue: 0.31, alpha: 1)
        case .dirt: return NSColor(calibratedRed: 0.52, green: 0.33, blue: 0.19, alpha: 1)
        case .immovable: return NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.28, alpha: 1)
        case .water: return NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.73, alpha: 1)
        case .lava: return NSColor(calibratedRed: 0.93, green: 0.25, blue: 0.09, alpha: 1)
        case .ore: return NSColor(calibratedRed: 0.55, green: 0.62, blue: 0.68, alpha: 1)
        case .crystal: return NSColor(calibratedRed: 0.12, green: 0.80, blue: 0.69, alpha: 1)
        case .recharge: return NSColor(calibratedRed: 0.40, green: 0.70, blue: 0.32, alpha: 1)
        case .hidden: return NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.19, alpha: 1)
        case .wallFace: return NSColor(calibratedRed: 0.32, green: 0.28, blue: 0.26, alpha: 1)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onExit?(); return }
        super.keyDown(with: event)
    }

    private func worldPosition(x: Double, z: Double) -> SCNVector3 {
        let elevation = world.elevation(atX: x, y: z) ?? 0
        return SCNVector3(Float(x) - Float(world.width) / 2,
                          elevation * NativeTerrainMesh.previewHeightScale + 0.48,
                          Float(z) - Float(world.height) / 2)
    }

    private func selectRaider(_ id: String) {
        selectedRaider = id
        for (identifier, marker) in raiderMarkers {
            marker.geometry?.firstMaterial?.emission.contents =
                identifier == id ? NSColor.systemYellow : NSColor.black
        }
        let placement = originalObjects?.rockRaiders.first(where: {
            $0.identifier == id
        })
        if let vehicle = placement?.drivingIdentifier {
            onInteractionMessage?("\(id) is driving \(vehicle); vehicle controls not yet ported.")
        } else {
            onInteractionMessage?("Selected original Rock Raider \(id). Click an exposed cavern tile to walk.")
        }
    }

    private func commandMove(to destination: NativeLevelNavigation.Position) {
        guard let id = selectedRaider, let marker = raiderMarkers[id] else { return }
        if let placement = originalObjects?.rockRaiders.first(where: {
            $0.identifier == id
        }), placement.drivingIdentifier != nil {
            onInteractionMessage?("Cannot move a driver independently until vehicles are ported.")
            return
        }
        let current = marker.presentation.position
        let from = NativeLevelNavigation.Position(
            x: Int(floor(Double(current.x) + Double(world.width) / 2)),
            y: Int(floor(Double(current.z) + Double(world.height) / 2)))
        guard let route = navigation.route(from: from, to: destination) else {
            onInteractionMessage?("No discovered walkable route to (\(destination.x), \(destination.y)).")
            return
        }
        guard route.count <= 512 else {
            onInteractionMessage?("Route exceeds 512 preview steps; select a closer destination.")
            return
        }
        marker.removeAllActions()
        let actions: [SCNAction] = route.dropFirst().map { tile in
            SCNAction.move(to: worldPosition(x: Double(tile.x) + 0.5,
                                              z: Double(tile.y) + 0.5),
                           duration: 0.25)
        }
        if !actions.isEmpty {
            marker.runAction(SCNAction.sequence(actions))
        }
        onInteractionMessage?("Rock Raider \(id): moving \(max(0, route.count - 1)) tiles to (\(destination.x), \(destination.y)).")
    }

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        let hits = hitTest(location, options: [.firstFoundOnly: false])
        // Select a real OL Pilot proxy first, but still permit terrain picks
        // through other objects such as building or ore markers.
        if let pilot = hits.first(where: { hit in
            raiderMarkers.values.contains(where: { $0 === hit.node })
        })?.node, let id = raiderMarkers.first(where: { $0.value === pilot })?.key {
            selectRaider(id)
        } else if let terrainHit = hits.first(where: {
            $0.node.name?.hasPrefix("Retail MAP /") == true
        }) {
            let point = terrainHit.worldCoordinates
            let x = Int(floor(Double(point.x) + Double(world.width) / 2))
            let z = Int(floor(Double(point.z) + Double(world.height) / 2))
            if let tile = world.tile(x: x, y: z) {
                onTileSelected?(tile)
                if selectedRaider != nil {
                    commandMove(to: NativeLevelNavigation.Position(x: x, y: z))
                }
            }
        }
        super.mouseDown(with: event) // Keep the native orbit camera controller.
    }
}

/// Offers a 3D view by default and an original 2D MAP debug view as fallback.
/// The parent holds strong references so the original game world remains
/// alive while the window is open; neither viewer modifies the source data.
final class NativeMissionWorkspace: NSView {
    private let level3D: NativeLevel3DView
    private let level2D: NativeLevelView
    private let mode: NSSegmentedControl
    private let status: NSTextField
    private let nerpsInfo: NSTextField
    private let tutorialMessage: NSTextField
    private let nerpsState: NativeNERPsGameState?
    private var nerpsTimer: Timer?
    private var previousTickTime: TimeInterval?
    private var nerpsHalted = false
    var originalCursor: NSCursor? {
        didSet {
            level3D.originalCursor = originalCursor
            level2D.originalCursor = originalCursor
        }
    }
    var onBack: (() -> Void)? {
        didSet {
            level3D.onExit = { [weak self] in self?.onBack?() }
            level2D.onExit = { [weak self] in self?.onBack?() }
        }
    }

    init(frame: NSRect, world: LevelWorld, objects: OriginalObjectList?,
         resources: GameResources, textureSet: String?,
         nerpsState: NativeNERPsGameState? = nil) throws {
        self.nerpsState = nerpsState
        self.nerpsInfo = NSTextField(labelWithString:
            nerpsState == nil ? "Original NERPs script unavailable" : "NERPs script loaded; preparing native callbacks")
        self.tutorialMessage = NSTextField(wrappingLabelWithString: "")
        self.tutorialMessage.isHidden = true
        self.level3D = try NativeLevel3DView(
            frame: frame, world: world, objects: objects,
            resources: resources, textureSet: textureSet)
        self.level2D = NativeLevelView(frame: frame, world: world)
        self.mode = NSSegmentedControl(labels: ["3D Terrain", "2D MAP"],
                                       trackingMode: .selectOne, target: nil, action: nil)
        self.status = NSTextField(labelWithString:
            "Original \(world.width)×\(world.height) tiles · Drag to orbit · Scroll to zoom · Click a tile")
        super.init(frame: frame)
        wantsLayer = true
        level2D.isHidden = true
        addSubview(level3D)
        addSubview(level2D)
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(changeMode(_:))
        addSubview(mode)
        status.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        status.textColor = .white
        status.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.85)
        status.drawsBackground = true
        status.lineBreakMode = .byTruncatingTail
        addSubview(status)
        nerpsInfo.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        nerpsInfo.textColor = .systemYellow
        nerpsInfo.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.85)
        nerpsInfo.drawsBackground = true
        nerpsInfo.lineBreakMode = .byTruncatingTail
        addSubview(nerpsInfo)
        tutorialMessage.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        tutorialMessage.textColor = .white
        tutorialMessage.backgroundColor = NSColor(calibratedWhite: 0.09, alpha: 0.94)
        tutorialMessage.drawsBackground = true
        addSubview(tutorialMessage)
        level3D.onTileSelected = { [weak self] tile in
            self?.status.stringValue =
                "Original (\(tile.x), \(tile.y)) · \(tile.terrain.rawValue) · \(tile.excavation.rawValue) · Height \(tile.heightCode)"
        }
        level3D.onInteractionMessage = { [weak self] message in
            self?.status.stringValue = message
        }
        if let objects {
            status.stringValue = "\(objects.rockRaiders.count) Rock Raiders • \(level3D.textureSummary) • click a Raider to select"
        } else {
            status.stringValue = "\(level3D.textureSummary) • original OL objects unavailable"
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        nerpsTimer?.invalidate()
        nerpsTimer = nil
        previousTickTime = nil
        guard window != nil, nerpsState != nil, !nerpsHalted else { return }
        nerpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                          repeats: true) { [weak self] _ in
            self?.advanceNERPs()
        }
    }

    deinit { nerpsTimer?.invalidate() }

    private func advanceNERPs() {
        guard let nerpsState, !nerpsHalted else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = previousTickTime.map { max(0, now - $0) } ?? 0
        previousTickTime = now
        do {
            let result = try nerpsState.tick(elapsedMilliseconds: Float(elapsed * 1000))
            // Text-only preview; original Next-arrow interaction and
            // synchronized Chief audio have not yet been implemented.
            if let text = nerpsState.messageText, !text.isEmpty {
                tutorialMessage.stringValue = text
                tutorialMessage.isHidden = false
            } else {
                tutorialMessage.isHidden = true
            }
            nerpsInfo.stringValue =
                "Original NERPs: \(nerpsState.completedTicks) ticks · " +
                "\(result.functionCalls) calls this tick · tutorial flags \(nerpsState.tutorialFlags)"
        } catch {
            nerpsHalted = true
            nerpsTimer?.invalidate()
            nerpsTimer = nil
            nerpsInfo.stringValue = "NERPs halted (unsupported original call): \(error)"
        }
    }

    override func layout() {
        super.layout()
        level3D.frame = bounds
        level2D.frame = bounds
        mode.frame = NSRect(x: max(12, bounds.width - 224),
                            y: max(10, bounds.height - 51),
                            width: 212, height: 34)
        status.frame = NSRect(x: 12, y: 12, width: max(0, bounds.width - 24),
                              height: 26)
        nerpsInfo.frame = NSRect(x: 12, y: 42, width: max(0, bounds.width - 24),
                                height: 19)
        tutorialMessage.frame = NSRect(x: 12, y: 70,
                                      width: max(0, bounds.width - 24), height: 70)
    }

    func focusActiveView() {
        window?.makeFirstResponder(mode.selectedSegment == 0 ? level3D : level2D)
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        level3D.isHidden = sender.selectedSegment != 0
        level2D.isHidden = sender.selectedSegment == 0
        status.stringValue = sender.selectedSegment == 0 ?
            "Original 3D MAP terrain · Drag to orbit · Scroll to zoom · Click a tile" :
            "Original 2D MAP terrain · Drag to pan · Scroll to zoom · Click a tile"
        focusActiveView()
    }
}
#endif
