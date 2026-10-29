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
    private(set) var terrainMesh: NativeTerrainMesh
    let originalObjects: OriginalObjectList?
    let textureSummary: String
    var onExit: (() -> Void)?
    private let excavation: NativeExcavationState
    var excavationState: NativeExcavationState { excavation }
    private var blockedBuildingTiles = Set<NativeLevelNavigation.Position>()
    private var navigation: NativeLevelNavigation {
        NativeLevelNavigation(world: world, excavated: excavation.excavated,
                              revealed: excavation.revealed, blockedBuildingTiles: blockedBuildingTiles)
    }
    private var terrainNodes: [SCNNode] = []
    private var terrainMaterials: [NativeTerrainMesh.Material: SCNMaterial] = [:]
    var onTerrainChanged: (() -> Void)?
    private var selectedWall: NativeLevelNavigation.Position?
    var hasSelectedWall: Bool { selectedWall != nil }
    var hasSelectedRaider: Bool { selectedRaider != nil }
    var isInFirstPerson: Bool { firstPersonRaider != nil }
    var onSelectionChanged: (() -> Void)?

    func clearSelection() {
        leaveFirstPerson()
        selectedWall = nil
        selectedRaider = nil
        selectedRaiders.removeAll()
        for marker in raiderMarkers.values {
            marker.geometry?.firstMaterial?.emission.contents = NSColor.black
            marker.enumerateChildNodes { node, _ in
                node.geometry?.materials.forEach { $0.emission.contents = NSColor.black }
            }
        }
        onSelectionChanged?()
    }

    func cancelSelectedOrder() {
        for id in selectedRaiders {
            guard let marker = raiderMarkers[id] else { continue }
            let position = marker.presentation.position
            motionGenerations[id] = UUID()
            marker.removeAllActions()
            drillingRaiders.remove(id)
            marker.position = position
            raiderModels[id]?.setMoving(false)
        }
        onInteractionMessage?("Selected Rock Raider orders cancelled.")
    }

    var showObjectMarkers = false {
        didSet {
            for placement in originalObjects?.placements ?? [] where !placement.isRockRaider {
                updatePlacementVisibility(placement)
            }
        }
    }
    private var placementNodes: [String: SCNNode] = [:]
    private var raiderMarkers: [String: SCNNode] = [:]
    private var selectedRaider: String?
    private var selectedRaiders = Set<String>()
    private var drillingRaiders = Set<String>()
    var selectionCount: Int32 { Int32(selectedRaiders.count) }
    private var raiderModels: [String: OriginalRaiderModel] = [:]
    private var objectModels: [String: OriginalMissionObjectModel] = [:]
    private(set) var modelDiagnostics: [String] = []
    private var modelTimer: Timer?
    private let overheadCamera = SCNNode()
    private let fog: NativeFirstPersonFog?
    private var fogSeconds: Double = 0
    private let overheadMotion: NativeOverheadCamera
    private let firstPersonCamera = SCNNode()
    private let firstPersonLight = SCNNode()
    private var firstPersonRaider: String?
    private var firstPersonController: NativeFirstPersonController?
    private var heldKeys = Set<UInt16>()
    private var frameClock = OriginalMissionClock()
    private var pausedAt: TimeInterval?
    var missionTimePaused = false {
        didSet {
            guard missionTimePaused != oldValue else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if missionTimePaused { pausedAt = now; heldKeys.removeAll() }
            else if let start = pausedAt {
                let duration = max(0, now - start)
                for model in raiderModels.values { model.rebaseTime(afterPausedFor: duration) }
                for model in objectModels.values { model.rebaseTime(afterPausedFor: duration) }
                pausedAt = nil
            }
            frameClock.reset()
            scene?.isPaused = missionTimePaused
            allowsCameraControl = !missionTimePaused && firstPersonRaider == nil && tutorialInputPolicy.canMoveCamera
        }
    }
    private(set) var modelSummary = "Original Raider models unavailable; diagnostic proxies"
    deinit { modelTimer?.invalidate() }
    var tutorialInputPolicy = NativeTutorialInputPolicy.unrestricted {
        didSet {
            if !tutorialInputPolicy.canMoveCamera { leaveFirstPerson() }
            allowsCameraControl = !missionTimePaused && firstPersonRaider == nil && tutorialInputPolicy.canMoveCamera
        }
    }
    var onTileSelected: ((LevelWorld.Tile) -> Void)?
    var originalCursor: NSCursor? {
        didSet { if let window { window.invalidateCursorRects(for: self) } }
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: originalCursor ?? .arrow)
    }
    var onInteractionMessage: ((String) -> Void)?
    var onRockRaiderSelected: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, world: LevelWorld, objects: OriginalObjectList?,
         resources: GameResources, textureSet: String?, config: LegoConfig? = nil, blockSize: Double = 40) throws {
        self.fog = NativeFirstPersonFog(config: config, level: world.identifier)
        self.overheadMotion = NativeOverheadCamera(config: config, blockSize: blockSize)
        self.world = world
        self.terrainMesh = try NativeTerrainMesh(world: world)
        self.originalObjects = objects
        self.excavation = NativeExcavationState(world: world)

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
        // The retail Building_Load shape is stored in each building's AE,
        // not the OL. Apply original solid cells to both clicked paths and
        // first-person sweeps; paired Shape points remain open entrances.
        if let config, let objects {
            for placement in objects.placements where !placement.isCamera && !placement.isRockRaider {
                guard let configured = config.valueUnderGame(["BuildingTypes", placement.type]),
                      placement.x >= 0, placement.y >= 0,
                      placement.x < Double(world.width), placement.y < Double(world.height) else { continue }
                var directory = configured.replacingOccurrences(of: "\\", with: "/")
                while directory.hasSuffix("/") { directory.removeLast() }
                let origin = NativeBuildingFootprints.Tile(x: Int(floor(placement.x)),
                                                            y: Int(floor(placement.y)))
                var shape: String?
                if OriginalModelActivities.safe(directory),
                   let basename = directory.split(separator: "/").last {
                    let aePath = "\(directory)/\(basename).ae"
                    do {
                        let bytes = try resources.data(at: aePath, maximumBytes: 1_000_000)
                        shape = try LegoConfig(data: bytes).valueUnderGame(["Shape"])
                    } catch {
                        modelDiagnostics.append("\(placement.identifier): missing building Shape; using origin-only clearance (\(error))")
                    }
                } else {
                    modelDiagnostics.append("\(placement.identifier): unsafe building AE path; using origin-only clearance")
                }
                do {
                    let tiles = try NativeBuildingFootprints.occupiedTiles(
                        shape: shape, origin: origin, headingDegrees: placement.headingDegrees)
                    for tile in tiles where tile.x >= 0 && tile.y >= 0 &&
                        tile.x < world.width && tile.y < world.height {
                        blockedBuildingTiles.insert(.init(x: tile.x, y: tile.y))
                    }
                } catch {
                    // Malformed AE shape must not silently make the building
                    // origin traversable. Do not invent missing footprint cells.
                    blockedBuildingTiles.insert(.init(x: origin.x, y: origin.y))
                    modelDiagnostics.append("\(placement.identifier): invalid building Shape; blocked origin only")
                }
            }
        }
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

        // Cache every original material before excavation exposes new seams.
        for kind in NativeTerrainMesh.Material.allCases {
            let material = SCNMaterial()
            material.diffuse.contents = Self.color(kind)
            if textureCatalog != nil, let id = Self.textureID(for: kind),
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
            terrainMaterials[kind] = material
        }
        for surface in terrainMesh.surfaces {
            guard let geometry = makeGeometry(surface),
                  let material = terrainMaterials[surface.material] else { continue }
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = "Retail MAP / \(surface.material.rawValue)"
            terrainNodes.append(node)
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
        let camera = overheadCamera
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = max(400, Double(max(world.width, world.height) * 3))
        camera.camera?.fieldOfView = 60
        camera.position = SCNVector3(centerX,
                                     centerY + 10,
                                     centerZ + 12)
        camera.look(at: SCNVector3(centerX, centerY, centerZ))
        scene.rootNode.addChildNode(camera)
        firstPersonCamera.camera = SCNCamera()
        firstPersonCamera.camera?.zNear = 0.03
        firstPersonCamera.camera?.zFar = fog?.distance ?? camera.camera?.zFar ?? 400
        scene.rootNode.addChildNode(firstPersonCamera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        func lightColor(_ name: String) -> NSColor? {
            guard let raw = config?.valueUnderGame(["Main", name]) else { return nil }
            let rgb = raw.split(separator: ":").compactMap { Double($0) }
            guard rgb.count == 3, rgb.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 255 }) else { return nil }
            return NSColor(calibratedRed: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255, alpha: 1)
        }
        ambient.light?.color = lightColor("AmbientRGB") ?? NSColor(calibratedWhite: 0.40, alpha: 1)
        if let color = lightColor("FPLightRGB") {
            firstPersonLight.light = SCNLight()
            firstPersonLight.light?.type = .omni
            firstPersonLight.light?.color = color
            firstPersonLight.isHidden = true
            firstPersonCamera.addChildNode(firstPersonLight)
        }
        scene.rootNode.addChildNode(ambient)

        let sharedTextures = config?.valueUnderGame(["Main", "SharedTextures"])
        let activities: Result<OriginalRaiderActivities, Error> = Result {
            guard let config else { throw OriginalModelActivities.AssetError.invalid("missing Lego.cfg") }
            return try OriginalRaiderActivities.load(config: config, resources: resources)
        }
        var objectAssets: [String: Result<OriginalMissionObjectAsset, Error>] = [:]
        // Every anchor is an existing OL identifier at its original coordinates.
        // Successful original geometry is visible in normal play; only missing
        // or unsupported models use the opt-in diagnostic proxy path.
        if let objects {
            for placement in objects.placements where !placement.isCamera {
                guard placement.x >= 0, placement.y >= 0,
                      placement.x < Double(world.width),
                      placement.y < Double(world.height) else { continue }
                let marker = SCNNode()
                marker.name = "Original OL: \(placement.identifier) / \(placement.type)"
                marker.position = worldPosition(x: placement.x, z: placement.y)
                marker.eulerAngles = SCNVector3(0, Float(placement.headingDegrees * .pi / 180), 0)
                scene.rootNode.addChildNode(marker)
                placementNodes[placement.identifier] = marker
                do {
                    if placement.isRockRaider {
                        let model = try OriginalRaiderModel(activities: activities.get(), resources: resources,
                                                           blockSize: blockSize, sharedTextures: sharedTextures)
                        marker.addChildNode(model.root)
                        raiderModels[placement.identifier] = model
                    } else {
                        let key = placement.type.lowercased()
                        if objectAssets[key] == nil {
                            objectAssets[key] = Result {
                                guard let config else { throw OriginalModelActivities.AssetError.invalid("missing Lego.cfg") }
                                return try OriginalMissionObjectAsset.load(type: placement.type,
                                                                           config: config, resources: resources)
                            }
                        }
                        let model = try OriginalMissionObjectModel(asset: objectAssets[key]!.get(), resources: resources,
                                                                   blockSize: blockSize, sharedTextures: sharedTextures)
                        marker.addChildNode(model.root)
                        objectModels[placement.identifier] = model
                    }
                } catch {
                    modelDiagnostics.append("\(placement.identifier) / \(placement.type): \(error)")
                    let geometry: SCNGeometry = placement.isRockRaider ?
                        SCNCapsule(capRadius: 0.22, height: 0.80) : SCNSphere(radius: 0.24)
                    let material = SCNMaterial()
                    material.diffuse.contents = placement.isRockRaider ? NSColor.systemYellow : NSColor.systemTeal
                    material.lightingModel = .blinn
                    geometry.materials = [material]
                    let proxy = SCNNode(geometry: geometry)
                    proxy.name = "Diagnostic proxy only"
                    proxy.position.y = OriginalObjectPresentation.diagnosticCenterHeight
                    marker.addChildNode(proxy)
                }
                updatePlacementVisibility(placement)
            }
        }
        modelSummary = "\(raiderModels.count) original Raider models • \(objectModels.count) original building/resource models"
        if !modelDiagnostics.isEmpty { modelSummary += " • \(modelDiagnostics.count) missing/unsupported (details in diagnostic tooltip)" }
        self.scene = scene
        self.pointOfView = camera
        defaultCameraController.target = SCNVector3(centerX, centerY, centerZ)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        modelTimer?.invalidate()
        modelTimer = nil
        frameClock.reset()
        heldKeys.removeAll()
        guard window != nil else { return }
        modelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            self?.advanceFrame()
        }
    }

    func endSession() {
        missionTimePaused = true
        modelTimer?.invalidate()
        modelTimer = nil
        // Invalidate already-dispatched SceneKit completions as well as the
        // running actions; neither may mutate the departed mission later.
        for (id, marker) in raiderMarkers {
            motionGenerations[id] = UUID()
            marker.removeAllActions()
        }
        drillingRaiders.removeAll()
    }

    private func makeGeometry(_ surface: NativeTerrainMesh.Surface) -> SCNGeometry? {
            // A few material-grouped triangle meshes replace thousands of
            // SCNNode cubes, allowing normal level sizes to stay responsive.
            let vertices: [SCNVector3] = surface.vertices.map {
                SCNVector3($0.x, $0.y, $0.z)
            }
            let normals: [SCNVector3] = surface.normals.map {
                SCNVector3($0.x, $0.y, $0.z)
            }
            guard vertices.count <= Int(UInt32.max) else { return nil }
            let indices = (0..<vertices.count).map { UInt32($0) }
            // UVs repeat original wall/ground bitmaps once per tile. For
            // vertical walls use their horizontal axis and height rather
            // than projecting the same flat color over the entire level.
            let uv: [CGPoint] = zip(surface.vertices, surface.normals).map { pair in
                let p = pair.0
                let n = pair.1
                if abs(n.y) >= 0.5 {
                    return CGPoint(x: CGFloat(p.x) + CGFloat(world.width) / 2, y: CGFloat(p.z) + CGFloat(world.height) / 2)
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
        return geometry
    }

    private func updatePlacementVisibility(_ placement: OriginalObjectList.Placement) {
        guard let node = placementNodes[placement.identifier] else { return }
        let discovered = excavation.tile(x: Int(placement.x), y: Int(placement.y))?.excavation.isDiscoveredCavern == true
        node.isHidden = OriginalObjectVisibility.isHidden(discovered: discovered,
            isRockRaider: placement.isRockRaider,
            hasOriginalModel: raiderModels[placement.identifier] != nil || objectModels[placement.identifier] != nil,
            showObjectMarkers: showObjectMarkers, isFirstPersonBody: placement.identifier == firstPersonRaider)
        if discovered && placement.isRockRaider { raiderMarkers[placement.identifier] = node }
    }

    private func refreshExcavatedTerrain() {
        guard let scene else { return }
        do {
            let updated = try NativeTerrainMesh(world: world, excavatedTiles: excavation.excavated, revealedTiles: excavation.revealed, rubbleTiles: excavation.rubble)
            let replacements = updated.surfaces.compactMap { surface -> SCNNode? in
                guard let geometry = makeGeometry(surface) else { return nil }
                // The opened floor reuses the existing original floor bitmap.
                if let material = terrainMaterials[surface.material] { geometry.materials = [material] }
                let node = SCNNode(geometry: geometry)
                node.name = "Retail MAP / \(surface.material.rawValue)"
                return node
            }
            terrainNodes.forEach { $0.removeFromParentNode() }
            replacements.forEach { scene.rootNode.addChildNode($0) }
            terrainNodes = replacements
            terrainMesh = updated
            for placement in originalObjects?.placements ?? [] { updatePlacementVisibility(placement) }
            firstPersonController?.navigation = navigation
            onTerrainChanged?()
        } catch { onInteractionMessage?("Cave rebuild failed: \(error)") }
    }

    func dismissWallSelection() { selectedWall = nil }

    func drillSelectedWall() {
        guard !missionTimePaused else { return }
        guard firstPersonRaider == nil, tutorialInputPolicy.canClickIcons,
              let wall = selectedWall, let id = selectedRaider,
              let marker = raiderMarkers[id],
              originalObjects?.rockRaiders.first(where: { $0.identifier == id })?.drivingIdentifier == nil
        else { onInteractionMessage?("Select a Rock Raider and a mineable wall first."); return }
        let point = marker.presentation.position
        let from = NativeLevelNavigation.Position(
            x: Int(floor(Double(point.x) + Double(world.width) / 2)),
            y: Int(floor(Double(point.z) + Double(world.height) / 2)))
        guard let order = excavation.plan(from: from, wall: wall) else {
            onInteractionMessage?("No reachable drilling face."); return
        }
        commandMove(to: .init(x: Double(order.approach.x) + 0.5,
                             y: Double(order.approach.y) + 0.5)) { [weak self, weak marker] in
            guard let self, marker != nil else { return }
            self.performDrill(id: id, order: order)

        }
    }

    private func performDrill(id: String, order: NativeExcavationState.DrillOrder) {
        guard !missionTimePaused else { return }
        guard let marker = raiderMarkers[id], drillingRaiders.insert(id).inserted else { return }
        let generation = motionGenerations[id]
        let duration = raiderModels[id]?.beginDrilling() ?? 0.75
        marker.eulerAngles = SCNVector3(0, Float(atan2(Double(order.wall.x - order.approach.x),
                                                     Double(order.wall.y - order.approach.y))), 0)
        marker.runAction(.wait(duration: duration)) { [weak self, weak marker] in
            DispatchQueue.main.async {
                guard let self, let marker, !self.missionTimePaused,
                      self.motionGenerations[id] == generation else { return }
                self.drillingRaiders.remove(id)
                self.raiderModels[id]?.setMoving(false)
                let p = marker.presentation.position
                let at = NativeLevelNavigation.Position(x: Int(floor(Double(p.x) + Double(self.world.width) / 2)),
                                                       y: Int(floor(Double(p.z) + Double(self.world.height) / 2)))
                guard self.excavation.finish(order, raiderAt: at) else { return }
                self.selectedWall = nil
                self.refreshExcavatedTerrain()
                self.onInteractionMessage?("Wall excavated; rubble remains and connected caverns are revealed.")
            }
        }
    }

    required init?(coder: NSCoder) { nil }

    /// These are the original SurfaceTexture identifiers, not arbitrary
    /// diagnostic colors (src/openlrr/game/GameCommon.h). Transition variants
    /// and wall orientation are still under development.
    private static func textureID(for material: NativeTerrainMesh.Material) -> UInt8? {
        switch material {
        case .rubble: return 0x10
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
        case .rubble: return NSColor.darkGray
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

    private static let overheadKeys: Set<UInt16> = [123, 124, 125, 126, 27, 24]
    private static let movementKeys: Set<UInt16> = [0, 1, 2, 13, 123, 124, 125, 126]

    override func keyDown(with event: NSEvent) {
        guard !missionTimePaused else { return }
        // F enters a selected original OL Raider's first-person view.
        // Key bindings are provisional until checked against original input.
        if event.keyCode == 3 {
            if !event.isARepeat {
                if firstPersonRaider == nil { enterFirstPerson() }
                else { leaveFirstPerson() }
            }
            return
        }
        if event.keyCode == 53 {
            if firstPersonRaider != nil { leaveFirstPerson() }
            else { onExit?() }
            return
        }
        if firstPersonRaider != nil {
            if Self.movementKeys.contains(event.keyCode) { heldKeys.insert(event.keyCode) }
            return
        }
        if Self.overheadKeys.contains(event.keyCode) { heldKeys.insert(event.keyCode); return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if Self.movementKeys.contains(event.keyCode) || Self.overheadKeys.contains(event.keyCode) {
            heldKeys.remove(event.keyCode)
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        heldKeys.removeAll() // Never keep walking when the window loses focus.
        return super.resignFirstResponder()
    }

    func enterFirstPerson() {
        guard !missionTimePaused else { return }
        guard tutorialInputPolicy.canMoveCamera else {
            onInteractionMessage?("NERPs tutorial currently restricts camera control.")
            return
        }
        guard let id = selectedRaider, let marker = raiderMarkers[id] else {
            onInteractionMessage?("Select an original Rock Raider before pressing F.")
            return
        }
        if originalObjects?.rockRaiders.first(where: { $0.identifier == id })?.drivingIdentifier != nil {
            onInteractionMessage?("First-person vehicle controls are not yet ported.")
            return
        }
        let current = marker.presentation.position
        let position = NativeLevelNavigation.Point(
            x: Double(current.x) + Double(world.width) / 2,
            y: Double(current.z) + Double(world.height) / 2)
        guard let controller = NativeFirstPersonController(
            navigation: navigation, position: position, heading: Double(marker.eulerAngles.y)) else {
            onInteractionMessage?("Raider is outside the discovered walkable area.")
            return
        }
        motionGenerations[id] = UUID()
        marker.removeAllActions() // Cancel click routing before direct control.
        marker.position = current
        raiderModels[id]?.setMoving(false)
        firstPersonRaider = id
        firstPersonController = controller
        heldKeys.removeAll()
        marker.isHidden = true // Camera is a separate scene node, not hidden.
        allowsCameraControl = false
        pointOfView = firstPersonCamera
        onSelectionChanged?()
        advanceFrame()
        onInteractionMessage?("First-person Raider \(id): W/S or ↑/↓ move, A/D or ←/→ turn; F/Esc return.")
    }

    func leaveFirstPerson() {
        guard let id = firstPersonRaider else { return }
        firstPersonRaider = nil
        firstPersonController = nil
        heldKeys.removeAll()
        raiderMarkers[id]?.isHidden = false
        raiderModels[id]?.setMoving(false)
        pointOfView = overheadCamera
        onSelectionChanged?()
        allowsCameraControl = !missionTimePaused && tutorialInputPolicy.canMoveCamera
        onInteractionMessage?("Returned to overhead view; click a Raider to select.")
    }

    /// Use live presentation positions, not the original static OL spawn:
    /// other Raiders can already be following clicked routes.
    private func otherRaiderObstacles(excluding id: String) -> [NativeDynamicCollision.Disc] {
        raiderMarkers.compactMap { entry -> NativeDynamicCollision.Disc? in
            guard entry.key != id else { return nil }
            let position = entry.value.presentation.position
            return NativeDynamicCollision.Disc(
                center: .init(x: Double(position.x) + Double(world.width) / 2,
                              y: Double(position.z) + Double(world.height) / 2),
                radius: NativeDynamicCollision.otherRaiderRadius)
        }
    }

    var rockRaiderCount: Int32 { Int32(raiderMarkers.count) }

    func gotoTutorialCamera(_ id: Int32) {
        guard let camera = pointOfView, firstPersonRaider == nil else { return }
        for tile in world.tutorialBlocks(id) {
            var target = worldPosition(x: Double(tile.x) + 0.5, z: Double(tile.y) + 0.5)
            target.y += 0.48 // Preserve the current tutorial camera's above-ground target.
            let previous = defaultCameraController.target
            let position = camera.position
            camera.position = SCNVector3(position.x + target.x - previous.x,
                                         position.y + target.y - previous.y,
                                         position.z + target.z - previous.z)
            defaultCameraController.target = target
            camera.look(at: target)
        }
    }

    func cameraAtTutorial(_ id: Int32) -> Int32 {
        let target = defaultCameraController.target
        let x = Int(floor(Double(target.x) + Double(world.width) / 2))
        let y = Int(floor(Double(target.z) + Double(world.height) / 2))
        return world.tutorialBlocks(id).contains { $0.x == x && $0.y == y } ? 1 : 0
    }

    func moveOverheadCamera(vector: CGPoint, zoom: Double = 0, seconds: Double) {
        guard !missionTimePaused, firstPersonRaider == nil, tutorialInputPolicy.canMoveCamera, let camera = pointOfView else { return }
        let target = defaultCameraController.target
        let position = camera.presentation.position
        let offset = NativeOverheadCamera.Offset(x: Double(position.x - target.x), y: Double(position.y - target.y), z: Double(position.z - target.z))
        let moved = overheadMotion.moved(offset: offset, horizontal: vector.x, vertical: vector.y, zoom: zoom, seconds: seconds)
        camera.position = SCNVector3(target.x + CGFloat(moved.x), target.y + CGFloat(moved.y), target.z + CGFloat(moved.z))
        camera.look(at: target)
    }

    /// Update first-person framing separately from movement. Original drill
    /// and idle ACT clips animate while direct controls are temporarily gated.
    private func synchronizeFirstPersonCamera(for id: String, marker: SCNNode, heading: Double) {
        NativeFirstPersonCameraTracking.synchronize(
            camera: firstPersonCamera,
            animatedAnchor: raiderModels[id]?.firstPersonCameraAnchor(),
            fallback: OriginalObjectPresentation.eyePosition(above: marker.position),
            heading: heading)
    }

    private func advanceFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = frameClock.advance(now: now, paused: missionTimePaused)
        guard !missionTimePaused else { return }
        firstPersonLight.isHidden = firstPersonRaider == nil
        if firstPersonRaider != nil, let fog {
            fogSeconds += min(elapsed, 0.1)
            let rgb = fog.color(seconds: fogSeconds)
            scene?.fogColor = NSColor(calibratedRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
            scene?.fogStartDistance = 0
            scene?.fogEndDistance = fog.distance
            scene?.fogDensityExponent = 1
        } else {
            scene?.fogStartDistance = 0
            scene?.fogEndDistance = 0
        }
        for model in raiderModels.values { model.update(time: now) }
        for model in objectModels.values { model.update(time: now) }
        // The original camera null continues animating during Activity_Drill.
        // Sync before the input/drilling early returns, not only after walking.
        if let id = firstPersonRaider, let marker = raiderMarkers[id],
           let controller = firstPersonController {
            synchronizeFirstPersonCamera(for: id, marker: marker, heading: controller.heading)
        }
        if firstPersonRaider == nil, window?.isKeyWindow == true {
            let horizontal = (heldKeys.contains(124) ? 1.0 : 0) - (heldKeys.contains(123) ? 1.0 : 0)
            let vertical = (heldKeys.contains(125) ? 1.0 : 0) - (heldKeys.contains(126) ? 1.0 : 0)
            let zoom = (heldKeys.contains(27) ? 1.0 : 0) - (heldKeys.contains(24) ? 1.0 : 0)
            if horizontal != 0 || vertical != 0 || zoom != 0 {
                moveOverheadCamera(vector: CGPoint(x: horizontal, y: vertical), zoom: zoom, seconds: elapsed)
            }
        }
        guard let id = firstPersonRaider, let marker = raiderMarkers[id],
              var controller = firstPersonController, tutorialInputPolicy.canMoveCamera else { return }
        let forward = (heldKeys.contains(13) || heldKeys.contains(126) ? 1.0 : 0.0) -
                      (heldKeys.contains(1) || heldKeys.contains(125) ? 1.0 : 0.0)
        let turn = (heldKeys.contains(2) || heldKeys.contains(124) ? 1.0 : 0.0) -
                   (heldKeys.contains(0) || heldKeys.contains(123) ? 1.0 : 0.0)
        if drillingRaiders.contains(id) { return }
        let moved = controller.advance(
            forward: forward, turn: turn, elapsed: elapsed,
            obstacles: otherRaiderObstacles(excluding: id))
        firstPersonController = controller
        if moved { marker.position = worldPosition(x: controller.position.x, z: controller.position.y) }
        marker.eulerAngles = SCNVector3(0, Float(controller.heading), 0)
        raiderModels[id]?.setMoving(moved)
        if forward > 0 && !moved {
            let at = NativeLevelNavigation.Position(x: Int(floor(controller.position.x)), y: Int(floor(controller.position.y)))
            let target = NativeLevelNavigation.Position(
                x: Int(floor(controller.position.x + sin(controller.heading) * 0.65)),
                y: Int(floor(controller.position.y + cos(controller.heading) * 0.65)))
            if abs(target.x - at.x) + abs(target.y - at.y) == 1, excavation.canDrill(target) {
                performDrill(id: id, order: .init(wall: target, approach: at, route: [at]))
            }
        }
        // Also refresh after the controller moves the Raider this frame.
        synchronizeFirstPersonCamera(for: id, marker: marker, heading: controller.heading)
    }

    private func worldPosition(x: Double, z: Double) -> SCNVector3 {
        let elevation = world.elevation(atX: x, y: z) ?? 0
        return SCNVector3(Float(x) - Float(world.width) / 2,
                          elevation * NativeTerrainMesh.previewHeightScale,
                          Float(z) - Float(world.height) / 2)
    }

    private func selectRaider(_ id: String, extending: Bool = false) {
        if extending {
            if !selectedRaiders.insert(id).inserted { selectedRaiders.remove(id) }
        } else { selectedRaiders = [id] }
        selectedRaider = selectedRaiders.contains(id) ? id : selectedRaiders.sorted().first
        selectedWall = nil
        onSelectionChanged?()
        onRockRaiderSelected?(id)
        for (identifier, marker) in raiderMarkers {
            let highlight = selectedRaiders.contains(identifier) ? NSColor(calibratedWhite: 0.15, alpha: 1) : NSColor.black
            marker.geometry?.firstMaterial?.emission.contents = highlight
            marker.enumerateChildNodes { part, _ in
                for material in part.geometry?.materials ?? [] { material.emission.contents = highlight }
            }
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

    private var motionGenerations: [String: UUID] = [:]

    private func commandMove(to destination: NativeLevelNavigation.Point, raiderID: String? = nil, onArrival: (() -> Void)? = nil) {
        guard !missionTimePaused else { return }
        guard let id = raiderID ?? selectedRaider, let marker = raiderMarkers[id] else { return }
        if let placement = originalObjects?.rockRaiders.first(where: {
            $0.identifier == id
        }), placement.drivingIdentifier != nil {
            onInteractionMessage?("Cannot move a driver independently until vehicles are ported.")
            return
        }
        let current = marker.presentation.position
        let from = NativeLevelNavigation.Point(
            x: Double(current.x) + Double(world.width) / 2,
            y: Double(current.z) + Double(world.height) / 2)
        guard let route = navigation.continuousRoute(from: from, to: destination) else {
            onInteractionMessage?("No route with enough clearance for the Rock Raider.")
            return
        }
        let goal = NativeDynamicCollision.Point(x: destination.x, y: destination.y)
        guard NativeDynamicCollision.sweepIsClear(
            from: goal, to: goal, obstacles: otherRaiderObstacles(excluding: id)) else {
            onInteractionMessage?("Another Rock Raider occupies that destination.")
            return
        }
        let generation = UUID()
        motionGenerations[id] = generation
        marker.removeAllActions()
        drillingRaiders.remove(id)
        marker.position = current // Retarget from the visible position without snapping.
        var previous = from
        let actions: [SCNAction] = route.dropFirst().map { target in
            let start = previous
            previous = target
            let distance = hypot(target.x - start.x, target.y - start.y)
            // Sample the original height field during motion, including slope
            // changes inside a segment. Planar motion follows a checked sweep.
            return SCNAction.customAction(duration: max(distance / 4.0, 0.001)) { [weak self] node, elapsed in
                let t = min(1.0, Double(elapsed) / max(distance / 4.0, 0.001))
                let x = start.x + (target.x - start.x) * t
                let y = start.y + (target.y - start.y) * t
                DispatchQueue.main.async { [weak self, weak node] in
                    guard let self, let node, !self.missionTimePaused, self.motionGenerations[id] == generation else { return }
                    let previous = NativeDynamicCollision.Point(
                        x: Double(node.position.x) + Double(self.world.width) / 2,
                        y: Double(node.position.z) + Double(self.world.height) / 2)
                    let next = NativeDynamicCollision.Point(x: x, y: y)
                    // A different Raider may have entered the planned route
                    // since it was clicked. Sweep each update to avoid passing
                    // through them; stopping is safer than a false auto-route.
                    if hypot(next.x - previous.x, next.y - previous.y) > 1e-8 &&
                       !NativeDynamicCollision.sweepIsClear(
                            from: previous, to: next,
                            obstacles: self.otherRaiderObstacles(excluding: id)) {
                        self.motionGenerations[id] = UUID()
                        node.removeAllActions()
                        self.raiderModels[id]?.setMoving(false)
                        self.onInteractionMessage?("Rock Raider \(id): path blocked by another Raider.")
                        return
                    }
                    node.position = self.worldPosition(x: x, z: y)
                    if distance > 0.0001 { node.eulerAngles = SCNVector3(0, Float(atan2(target.x - start.x, target.y - start.y)), 0) }
                }
            }
        }
        raiderModels[id]?.setMoving(true)
        marker.runAction(SCNAction.sequence(actions)) { [weak self] in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.missionTimePaused, self.motionGenerations[id] == generation else { return }
                self.raiderModels[id]?.setMoving(false)
                onArrival?()
            }
        }
        onInteractionMessage?("Rock Raider \(id): walking to the clicked position with wall clearance.")
    }

    override func mouseDown(with event: NSEvent) {
        guard !missionTimePaused else { return }
        if firstPersonRaider != nil { return } // Do not send first-person clicks to orbit controls.
        let location = convert(event.locationInWindow, from: nil)
        let hits = hitTest(location, options: [.firstFoundOnly: false])
        // Select a real OL Pilot proxy first, but still permit terrain picks
        // through other objects such as building or ore markers.
        let pickedRaider = hits.compactMap { hit -> String? in
            OriginalObjectPresentation.placementIdentifier(containing: hit.node, anchors: raiderMarkers)
        }.first
        if let id = pickedRaider {
            if tutorialInputPolicy.canSelectObjects { selectRaider(id, extending: event.modifierFlags.contains(.shift)) }
        } else if tutorialInputPolicy.canClickMap,
                  let terrainHit = hits.first(where: {
            $0.node.name?.hasPrefix("Retail MAP /") == true
        }) {
            let point = terrainHit.worldCoordinates
            let normal = terrainHit.worldNormal
            let x = Int(floor(Double(point.x - normal.x * 0.01) + Double(world.width) / 2))
            let z = Int(floor(Double(point.z - normal.z * 0.01) + Double(world.height) / 2))
            selectedWall = excavation.canDrill(.init(x: x, y: z)) ? .init(x: x, y: z) : nil
            if let tile = excavation.tile(x: x, y: z) {
                onTileSelected?(tile)
                if selectedRaider != nil && selectedWall == nil {
                    let ids = selectedRaiders.sorted()
                    for (index, id) in ids.enumerated() {
                        let angle = Double(index) * 2 * .pi / Double(max(1, ids.count))
                        let radius = ids.count > 1 ? max(0.5, Double(ids.count) * 0.12) : 0
                        commandMove(to: .init(x: Double(point.x) + Double(world.width) / 2 + cos(angle) * radius,
                                              y: Double(point.z) + Double(world.height) / 2 + sin(angle) * radius), raiderID: id)
                    }
                }
            }
        }
        if tutorialInputPolicy.canMoveCamera { super.mouseDown(with: event) }
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
    private let missionHUD: OriginalMissionMessageUI
    private let briefing: OriginalMissionBriefingUI?
    private let briefingAudio = OriginalMissionBriefingAudio()
    private var startBriefingAudio: (() -> String)?
    private var startup = OriginalMissionStartupGate()
    private(set) var startupStatus = "Preparing original mission briefing"
    var isBriefingActive: Bool { briefing?.isActive == true }
    var onGameplayStart: (() -> Void)?
    var onStartupStatus: ((String) -> Void)?
    private let panels: OriginalMissionPanels
    private let commands: OriginalMissionCommands
    private var commandPage = OriginalMissionCommandCatalog.Page.main
    private let optionsButton = NSButton(title: "Mission options ▾", target: nil, action: nil)
    private let optionsPanel = NSVisualEffectView()
    private var toastGeneration = 0
    private let scriptButton = NSButton(checkboxWithTitle: "Run NERPs", target: nil, action: nil)
    private let diagnosticsButton = NSButton(checkboxWithTitle: "Diagnostics", target: nil, action: nil)
    private let nerpsState: NativeNERPsGameState?
    private let nerpsAudio = OriginalNERPsAudio()
    private let caveAudio = OriginalMenuAudio()
    private var startCaveAudio: (() -> Void)?
    private var nerpsTimer: Timer?
    private var scriptClock = OriginalMissionClock()
    private var nerpsHalted = false
    var originalCursor: NSCursor? {
        didSet {
            level3D.originalCursor = originalCursor
            level2D.originalCursor = originalCursor
            missionHUD.originalCursor = originalCursor
            commands.originalCursor = originalCursor
            panels.originalCursor = originalCursor
            briefing?.originalCursor = originalCursor
        }
    }
    var onBack: (() -> Void)? {
        didSet {
            level3D.onExit = { [weak self] in self?.onBack?() }
            level2D.onExit = { [weak self] in self?.onBack?() }
            briefing?.onExit = { [weak self] in self?.onBack?() }
        }
    }

    init(frame: NSRect, world: LevelWorld, objects: OriginalObjectList?,
         resources: GameResources, textureSet: String?,
         nerpsState: NativeNERPsGameState? = nil, config: LegoConfig? = nil, blockSize: Double = 40,
         wadURL: URL? = nil, extraAudioRoot: URL? = nil,
         openingInput: OriginalMissionBriefingInput = OriginalMissionBriefingUI.heldInput()) throws {
        self.nerpsState = nerpsState
        let definition = try OriginalMissionBriefingDefinition(config: config, levelIdentifier: world.identifier)
        // ObjectiveText is optional in Objective_LoadLevel (568–573). Keep
        // its blank initial state and normal dismissal/latch, not a skip to
        // gameplay. A configured unreadable/malformed file is an honest error.
        let bytes = try definition.objectiveTextPath.map {
            try resources.data(at: $0, maximumBytes: OriginalMissionBriefingText.maximumFileBytes)
        } ?? Data()
        let text = try OriginalMissionBriefingText(data: bytes, levelIdentifier: world.identifier)
        briefing = try OriginalMissionBriefingUI(definition: definition, text: text,
                                                resources: resources, openingInput: openingInput)
        self.nerpsInfo = NSTextField(labelWithString:
            nerpsState == nil ? "Original NERPs script unavailable" : "NERPs script loaded; preparing native callbacks")
        self.missionHUD = OriginalMissionMessageUI(resources: resources, config: config)
        self.panels = OriginalMissionPanels(resources: resources, config: config)
        self.commands = OriginalMissionCommands(resources: resources, config: config)
        self.level3D = try NativeLevel3DView(
            frame: frame, world: world, objects: objects,
            resources: resources, textureSet: textureSet, config: config, blockSize: blockSize)
        self.level2D = NativeLevelView(frame: frame, world: world)
        self.mode = NSSegmentedControl(labels: ["3D Terrain", "2D MAP"],
                                       trackingMode: .selectOne, target: nil, action: nil)
        self.status = NSTextField(labelWithString:
            "Original \(world.width)×\(world.height) tiles · Drag to orbit · Scroll to zoom · Click a tile")
        super.init(frame: frame)
        level3D.missionTimePaused = isBriefingActive
        level2D.missionInputBlocked = isBriefingActive
        nerpsState?.objectiveShowing = { [weak self] in self?.briefing?.objectiveShowing == true }
        briefing?.onDismiss = { [weak self] in self?.dismissInitialBriefing() }
        if let briefing {
            startBriefingAudio = { [weak self] in
                self?.briefingAudio.start(definition: briefing.definition, config: config,
                    resources: resources, wadURL: wadURL, extraRoot: extraAudioRoot) ?? "Briefing speech stopped"
            }
            startupStatus = (["Original mission briefing"] + briefing.diagnostics).joined(separator: " · ")
        }
        nerpsState?.tutorialGroundValue = { [weak self] id in self?.level3D.excavationState.tutorialGroundValue(id) ?? 0 }
        nerpsState?.gotoTutorialCamera = { [weak self] id in self?.level3D.gotoTutorialCamera(id) }
        nerpsState?.cameraAtTutorial = { [weak self] id in self?.level3D.cameraAtTutorial(id) ?? 0 }
        nerpsState?.rockRaidersOnLevel = { [weak self] in self?.level3D.rockRaiderCount ?? 0 }
        if let config, let wadURL {
            startCaveAudio = { [weak self] in
                _ = self?.caveAudio.start(config: config, resources: resources, beside: wadURL,
                    additionalAudioRoot: extraAudioRoot, sampleName: "SFX_AmbientLoop")
            }
        }
        let soundFlag = config?.valueUnderGame(["Main", "SoundOn"])?.uppercased() ?? "TRUE"
        nerpsState?.playMessageSound = { [weak self] path in
            self?.nerpsAudio.start(path: path, resources: resources, wadURL: wadURL,
                                  extraRoot: extraAudioRoot,
                                  soundEnabled: !["FALSE", "NO", "OFF", "0"].contains(soundFlag))
        }
        level2D.excavationState = level3D.excavationState
        level3D.onTerrainChanged = { [weak self] in
            self?.level2D.needsDisplay = true
            self?.refreshWallControls()
        }
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
        addSubview(panels)
        panels.onCameraControl = { [weak self] vector, elapsed in
            self?.level3D.moveOverheadCamera(vector: vector, seconds: elapsed)
        }
        addSubview(missionHUD)
        addSubview(commands)
        commands.onCommand = { [weak self] action in self?.performCommand(action) }
        commands.onBack = { [weak self] in self?.returnToCommands() }
        level3D.onSelectionChanged = { [weak self] in
            guard let self else { return }
            self.nerpsState?.reportRockRaiderSelection(count: self.level3D.selectionCount)
            self.commandPage = self.level3D.isInFirstPerson ? .firstPerson : self.level3D.hasSelectedRaider ? .raider : .main
            self.refreshWallControls()
        }
        optionsPanel.material = .hudWindow
        optionsPanel.blendingMode = .withinWindow
        optionsPanel.state = .active
        optionsPanel.isHidden = true
        addSubview(optionsPanel)
        optionsButton.target = self
        optionsButton.action = #selector(toggleOptions)
        optionsButton.isHidden = !ProcessInfo.processInfo.arguments.contains("--native-diagnostics")
        addSubview(optionsButton)
        refreshWallControls()
        missionHUD.onAdvance = { [weak self] in self?.advanceTutorialMessage() }
        diagnosticsButton.target = self
        diagnosticsButton.action = #selector(toggleDiagnostics(_:))
        optionsPanel.addSubview(diagnosticsButton)
        scriptButton.state = .on
        scriptButton.isEnabled = nerpsState != nil
        scriptButton.toolTip = "Pause or resume the original mission script without resetting its registers or timers."
        scriptButton.target = self
        scriptButton.action = #selector(toggleScript(_:))
        optionsPanel.addSubview(scriptButton)
        setDiagnosticsVisible(false)
        level3D.onTileSelected = { [weak self] tile in
            if let self {
                self.commandPage = self.level3D.hasSelectedWall ? .wall : self.level3D.hasSelectedRaider ? .raider : .main
                self.refreshWallControls()
            }
            self?.status.stringValue =
                "Original (\(tile.x), \(tile.y)) · \(tile.terrain.rawValue) · \(tile.excavation.rawValue) · Height \(tile.heightCode)"
        }
        level3D.onInteractionMessage = { [weak self] message in
            self?.showActionMessage(message)
        }
        // A real click on an original OL Pilot marker changes the script's
        // GetMiniFigureSelected result during the next NERPs VM tick.
        level3D.onRockRaiderSelected = { [weak self] _ in
            if let self { self.nerpsState?.reportRockRaiderSelection(count: self.level3D.selectionCount) }
        }
        if let briefing { addSubview(briefing) }
        refreshTutorialMessage()
        status.toolTip = level3D.modelDiagnostics.joined(separator: "\n")
        if let objects {
            status.stringValue = "\(objects.rockRaiders.count) Rock Raiders • \(level3D.textureSummary) • \(level3D.modelSummary) • click a Raider to select"
        } else {
            status.stringValue = "\(level3D.textureSummary) • original OL objects unavailable"
        }
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        nerpsTimer?.invalidate()
        nerpsTimer = nil
        scriptClock.reset()
        guard window != nil else {
            if startup.isAttached { endSession() }
            return
        }
        startup.attach()
        updateStartup()
        guard !startup.hasExited else { return }
        // This clock also drains the opening gesture and starts the speech in
        // missions lacking NERPs, or after a correctly halted unsupported call.
        nerpsTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0,
                                          repeats: true) { [weak self] _ in
            self?.advanceNERPs()
        }
    }

    deinit { nerpsTimer?.invalidate() }

    func endSession() {
        startup.exit()
        nerpsTimer?.invalidate()
        nerpsTimer = nil
        briefing?.cancel()
        briefingAudio.stop()
        nerpsAudio.stop()
        caveAudio.stop()
        level3D.endSession()
        level2D.missionInputBlocked = true
        scriptClock.reset()
    }

    private func updateStartup() {
        guard startup.isAttached, !startup.hasExited else { return }
        briefing?.drainOpeningInput()
        if startup.claimSpeechStart(briefingShowing: briefing?.objectiveShowing == true) {
            startupStatus = ([startBriefingAudio?() ?? "Original briefing speech unavailable"] +
                             (briefing?.diagnostics ?? [])).joined(separator: " · ")
            onStartupStatus?(startupStatus)
        }
        if startup.claimGameplayStart(briefingActive: isBriefingActive) {
            startCaveAudio?()
            onGameplayStart?()
        }
    }

    private func dismissInitialBriefing() {
        guard startup.isAttached, !startup.hasExited else { return }
        briefingAudio.stop()
        nerpsState?.reportInitialBriefingDismissed()
        scriptClock.reset()
        level3D.missionTimePaused = false
        level2D.missionInputBlocked = false
        refreshWallControls()
        refreshTutorialMessage()
        updateStartup()
        focusActiveView()
    }

    private func advanceNERPs() {
        guard startup.isAttached, !startup.hasExited else { return }
        updateStartup()
        let elapsed = scriptClock.advance(now: ProcessInfo.processInfo.systemUptime,
                                          paused: isBriefingActive || nerpsState?.isPaused == true)
        // The launch-click drain happens before entering the original game
        // loop. Do not let !GetObjectiveShowing bypass the pending briefing.
        guard briefing?.state.permitsScriptTick != false,
              let nerpsState, !nerpsHalted, !nerpsState.isPaused else { return }
        do {
            let result = try nerpsState.tick(elapsedMilliseconds: Float(elapsed * 1000))
            // Original tutorial script flags now gate both actual mission views.
            let policy = nerpsState.inputPolicy
            level3D.tutorialInputPolicy = policy
            level2D.tutorialInputPolicy = policy
            refreshWallControls()
            // Original message text and one-shot acknowledgement.
            refreshTutorialMessage()
            nerpsInfo.stringValue =
                "Original NERPs: \(nerpsState.completedTicks) ticks · " +
                "\(result.functionCalls) calls this tick · tutorial flags \(nerpsState.tutorialFlags)"
        } catch {
            nerpsHalted = true
            nerpsInfo.stringValue = "NERPs halted (unsupported original call): \(error)"
            nerpsInfo.toolTip = nerpsInfo.stringValue
            diagnosticsButton.state = .on
            setDiagnosticsVisible(true)
            refreshTutorialMessage()
        }
    }

    @objc private func toggleScript(_ sender: NSButton) {
        guard let state = nerpsState else { return }
        state.isPaused = sender.state != .on
        scriptClock.reset() // Do not charge diagnostic pause time on resume.
        let policy = state.isPaused ? NativeTutorialInputPolicy.unrestricted : state.inputPolicy
        level3D.tutorialInputPolicy = policy
        level2D.tutorialInputPolicy = policy
        refreshWallControls()
        if state.isPaused {
            missionHUD.update(text: nil, canAdvance: false, hideArrow: true)
        } else { refreshTutorialMessage() }
        if nerpsHalted {
            nerpsInfo.toolTip = "The script stopped on an unsupported callback. Pausing releases tutorial input restrictions; resuming requires that callback to be implemented."
        }
        focusActiveView()
    }

    private func refreshWallControls() {
        if commandPage == .wall && !level3D.hasSelectedWall {
            commandPage = level3D.hasSelectedRaider ? .raider : .main
        }
        commands.isHidden = mode.selectedSegment != 0
        panels.isHidden = mode.selectedSegment != 0
        panels.cameraPermitted = !isBriefingActive && !level3D.isInFirstPerson && level3D.tutorialInputPolicy.canMoveCamera
        let permitted = !isBriefingActive && (nerpsState == nil || nerpsState!.isPaused || nerpsState!.inputPolicy.canClickIcons)
        commands.update(page: commandPage, hasRaider: level3D.hasSelectedRaider, permitted: permitted)
    }

    private func performCommand(_ action: String) {
        guard !isBriefingActive, !startup.hasExited else { return }
        switch action {
        case "Dig":
            nerpsState?.reportDigIconClick()
            level3D.drillSelectedWall()
        case "DeselectDig": level3D.cancelSelectedOrder()
        case "BuildBuilding":
            nerpsState?.reportBuildIconClick()
            commandPage = .buildings
        case "GotoFirstPerson": level3D.enterFirstPerson()
        case "GotoTopView": level3D.leaveFirstPerson()
        default: return
        }
        refreshWallControls()
        focusActiveView()
    }

    private func returnToCommands() {
        guard !isBriefingActive, !startup.hasExited else { return }
        nerpsState?.reportBackIconClick()
        level3D.clearSelection()
        commandPage = .main
        refreshWallControls()
        focusActiveView()
    }

    private func showActionMessage(_ message: String) {
        toastGeneration += 1
        let generation = toastGeneration
        status.stringValue = message
        status.toolTip = message
        status.isHidden = diagnosticsButton.state != .on
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.toastGeneration == generation,
                  self.diagnosticsButton.state != .on else { return }
            self.status.isHidden = true
        }
    }

    @objc private func toggleOptions() {
        optionsPanel.isHidden.toggle()
        optionsButton.title = optionsPanel.isHidden ? "Mission options ▾" : "Mission options ▴"
        if optionsPanel.isHidden { focusActiveView() }
    }

    private func refreshTutorialMessage() {
        if isBriefingActive {
            // Objective_Update displays the configured Space prompt through
            // the ordinary bottom panel; NERP messages retain precedence.
            let text = briefing?.definition.messageText(briefingActive: true,
                nerpsText: nerpsState?.messageText, messagePermit: nerpsState?.messagePermit ?? true)
            missionHUD.update(text: text, canAdvance: false, hideArrow: true)
            return
        }
        missionHUD.update(text: nerpsState?.messageText,
                          canAdvance: nerpsState?.messageNeedsAdvance ?? false,
                          hideArrow: (nerpsState?.nextArrowDisabled ?? true) ||
                                     (nerpsState?.suppressMessageArrow ?? true))
    }

    private func advanceTutorialMessage() {
        guard !isBriefingActive else { return }
        guard let state = nerpsState, state.messageNeedsAdvance,
              !state.nextArrowDisabled, !state.suppressMessageArrow else { return }
        state.advanceMessage()
        refreshTutorialMessage()
        focusActiveView()
    }

    private func setDiagnosticsVisible(_ visible: Bool) {
        level3D.showObjectMarkers = visible && ProcessInfo.processInfo.arguments.contains("--native-diagnostics")
        mode.isHidden = !visible
        status.isHidden = !visible
        nerpsInfo.isHidden = !visible
    }

    @objc private func toggleDiagnostics(_ sender: NSButton) {
        setDiagnosticsVisible(sender.state == .on)
        focusActiveView()
    }

    override func layout() {
        super.layout()
        level3D.frame = bounds
        level2D.frame = bounds
        mode.frame = NSRect(x: 174,
                            y: max(10, bounds.height - 51),
                            width: 212, height: 34)
        status.frame = NSRect(x: 12, y: 12, width: max(0, bounds.width - 150),
                              height: 26)
        nerpsInfo.frame = NSRect(x: 12, y: 42, width: max(0, bounds.width - 24),
                                height: 19)
        missionHUD.frame = bounds
        briefing?.frame = bounds
        panels.frame = bounds
        // A full-canvas flipped overlay shares the panels' HUD transform.
        // Surround art can extend left/up of the fixed (565,18) icon origin.
        commands.frame = bounds
        optionsButton.frame = NSRect(x: 12, y: max(0, bounds.height - 34), width: 150, height: 26)
        optionsPanel.frame = NSRect(x: 12, y: max(0, bounds.height - 106), width: 240, height: 68)
        diagnosticsButton.frame = NSRect(x: 12, y: 8, width: 210, height: 24)
        scriptButton.frame = NSRect(x: 12, y: 36, width: 210, height: 24)
        // Diagnostics sit above the message panel when explicitly enabled.
        status.frame.origin.y = 150
        nerpsInfo.frame.origin.y = 180
    }

    func focusActiveView() {
        if let briefing, briefing.isActive { window?.makeFirstResponder(briefing) }
        else { window?.makeFirstResponder(mode.selectedSegment == 0 ? level3D : level2D) }
    }

    @objc private func changeMode(_ sender: NSSegmentedControl) {
        if sender.selectedSegment != 0 { level3D.leaveFirstPerson() }
        level3D.isHidden = sender.selectedSegment != 0
        level2D.isHidden = sender.selectedSegment == 0
        refreshWallControls()
        status.stringValue = sender.selectedSegment == 0 ?
            "Original 3D MAP terrain · Drag to orbit · Scroll to zoom · Click a tile" :
            "Original 2D MAP terrain · Drag to pan · Scroll to zoom · Click a tile"
        focusActiveView()
    }
}
#endif
