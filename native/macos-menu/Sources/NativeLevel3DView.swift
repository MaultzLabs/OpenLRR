#if os(macOS)
import AppKit
import SceneKit

/// Native Apple Silicon 3D inspection of real retail MAP terrain.
/// SceneKit is the first rendering bridge while the original renderer,
/// textures, objects and gameplay logic are being ported. The meshes are
/// derived exclusively from the user's original files.
final class NativeLevel3DView: SCNView {
    let world: LevelWorld
    let terrainMesh: NativeTerrainMesh
    var onTileSelected: ((LevelWorld.Tile) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, world: LevelWorld) throws {
        self.world = world
        self.terrainMesh = try NativeTerrainMesh(world: world)
        super.init(frame: frame, options: nil)
        backgroundColor = NSColor(calibratedRed: 0.06, green: 0.075, blue: 0.09, alpha: 1)
        autoenablesDefaultLighting = true
        allowsCameraControl = true
        preferredFramesPerSecond = 60
        rendersContinuously = false

        let scene = SCNScene()
        scene.background.contents = backgroundColor

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
            let geometry = SCNGeometry(
                sources: [SCNGeometrySource(vertices: vertices),
                          SCNGeometrySource(normals: normals)],
                elements: [SCNGeometryElement(indices: indices,
                                              primitiveType: .triangles)])
            let material = SCNMaterial()
            material.diffuse.contents = Self.color(surface.material)
            material.lightingModel = .blinn
            material.isDoubleSided = true
            material.specular.contents = NSColor(calibratedWhite: 0.14, alpha: 1)
            geometry.materials = [material]
            let node = SCNNode(geometry: geometry)
            node.name = "Retail MAP / \(surface.material.rawValue)"
            scene.rootNode.addChildNode(node)
        }

        let start = world.initialCameraTile
        let centerX = Float(start.x) + 0.5 - Float(world.width) / 2
        let centerZ = Float(start.y) + 0.5 - Float(world.height) / 2
        let centerY = Float(world.surfaceMap.value(x: start.x, y: start.y) ?? 0)
                      * NativeTerrainMesh.previewHeightScale
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.1
        camera.camera?.zFar = max(400, Double(max(world.width, world.height) * 3))
        camera.camera?.fieldOfView = 60
        camera.position = SCNVector3(centerX,
                                     centerY + 16,
                                     centerZ + 19)
        camera.look(at: SCNVector3(centerX, centerY, centerZ))
        scene.rootNode.addChildNode(camera)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(calibratedWhite: 0.40, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        self.scene = scene
        self.pointOfView = camera
    }

    required init?(coder: NSCoder) { nil }

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

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if let intersection = hitTest(location, options: [.firstFoundOnly: true]).first {
            let point = intersection.worldCoordinates
            let x = Int(floor(Double(point.x) + Double(world.width) / 2))
            let z = Int(floor(Double(point.z) + Double(world.height) / 2))
            if let tile = world.tile(x: x, y: z) {
                onTileSelected?(tile)
            }
        }
        super.mouseDown(with: event) // Keep the native camera controller working.
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

    init(frame: NSRect, world: LevelWorld) throws {
        self.level3D = try NativeLevel3DView(frame: frame, world: world)
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
        level3D.onTileSelected = { [weak self] tile in
            self?.status.stringValue =
                "Original (\(tile.x), \(tile.y)) · \(tile.terrain.rawValue) · \(tile.excavation.rawValue) · Height \(tile.heightCode)"
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        level3D.frame = bounds
        level2D.frame = bounds
        mode.frame = NSRect(x: max(12, bounds.width - 224),
                            y: max(10, bounds.height - 51),
                            width: 212, height: 34)
        status.frame = NSRect(x: 12, y: 12, width: max(0, bounds.width - 24),
                              height: 26)
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
