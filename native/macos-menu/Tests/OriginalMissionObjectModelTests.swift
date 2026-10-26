import Foundation
#if os(macOS)
import AppKit
import SceneKit
#endif

// Synthetic config, WWAD, LWOB and LWSC fixtures only. No original game art.
private enum MissionObjectFixture {
    struct Asset {
        let path: String
        let bytes: Data
        var flags: UInt32 = 1
    }

    static let directory = "Fixture/DepotCustom"
    static let scenePath = directory + "/Waiting.lws"
    static let meshPath = directory + "/Body.lwo"
    static let sharedMeshPath = "Fixture/Shared/Body.lwo"

    static func u32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    static func be16(_ value: UInt16) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }
    static func be32(_ value: UInt32) -> [UInt8] { Array(u32(value).reversed()) }
    static func point(_ x: Float, _ y: Float, _ z: Float) -> [UInt8] {
        be32(x.bitPattern) + be32(y.bitPattern) + be32(z.bitPattern)
    }
    static func chunk(_ name: String, _ payload: [UInt8]) -> [UInt8] {
        Array(name.utf8) + be32(UInt32(payload.count)) + payload + (payload.count % 2 == 1 ? [0] : [])
    }
    static func mesh(size: Float = 1) -> Data {
        let points = point(0, 0, 0) + point(size, 0, 0) + point(size, 0, size) + point(0, 0, size)
        let names = Array("Fixture".utf8) + [0]
        let polygon = be16(4) + be16(0) + be16(1) + be16(2) + be16(3) + be16(1)
        let color = names + Array("COLR".utf8) + be16(4) + [80, 90, 100, 0]
        let body = Array("LWOB".utf8) + chunk("PNTS", points) + chunk("SRFS", names) +
            chunk("POLS", polygon) + chunk("SURF", color)
        return Data(Array("FORM".utf8) + be32(UInt32(body.count)) + body)
    }
    static let uv = Data("""
    2
    1
    Fixture
    Fixture.bmp
    1
    0 4
    0 0
    1 0
    1 1
    0 1
    """.utf8)

    static func wad(_ assets: [Asset]) -> Data {
        var bytes = Array("WWAD".utf8) + u32(UInt32(assets.count))
        for asset in assets { bytes += Array(asset.path.utf8) + [0] }
        for asset in assets { bytes += Array(("Z:\\Synthetic\\" + asset.path).utf8) + [0] }
        var offset = bytes.count + assets.count * 16
        for asset in assets {
            bytes += u32(asset.flags) + u32(UInt32(asset.bytes.count)) +
                u32(UInt32(asset.bytes.count)) + u32(UInt32(offset))
            offset += asset.bytes.count
        }
        for asset in assets { bytes.append(contentsOf: asset.bytes) }
        return Data(bytes)
    }
    static func resources(_ assets: [Asset]) throws -> GameResources {
        try GameResources(archives: [(0, wad(assets))])
    }
    static func config(crystal: String = "Fixture\\Resources\\Crystal",
                       color: String? = "32:128:224", directory: String = "Fixture\\DepotCustom") throws -> LegoConfig {
        try LegoConfig(text: """
        Lego* {
          Main {
            SharedObjects Fixture\\Shared\\
            SharedTextures Fixture\\Textures\\
            \(color.map { "PowerCrystalRGB " + $0 } ?? "")
          }
          BuildingTypes {
            Toolstation \(directory)
            SecretHub \(directory)
          }
          MiscObjects {
            Crystal \(crystal)
            Ore Fixture\\Resources\\Ore
            ProcessedOre Fixture\\Resources\\Stud.LWO
          }
        }
        """)
    }
    static func definition(scale: String? = nil, looping: String? = nil,
                           lws: String = "TRUE", file: String = "Waiting") -> Data {
        Data("""
        Lego* {
          \(scale.map { "Scale " + $0 } ?? "")
          Activities {
            !Activity_Stand IdleOnly
          }
          IdleOnly {
            FILE \(file)
            LWSFILE \(lws)
            \(looping.map { "LOOPING " + $0 } ?? "")
          }
        }
        """.utf8)
    }
    static func scene(reference: String = "Z:\\Author\\Body.lwo", first: Int = 4, last: Int = 20) -> Data {
        Data("""
        LWSC
        1
        FirstFrame \(first)
        LastFrame \(last)
        FramesPerSecond 10
        AddNullObject FixtureGroup
        ObjectMotion (unnamed)
        9
        1
        7 8 9 0 0 0 1 1 1
        0 0 0 0 0
        LoadObject \(reference)
        ObjectMotion (unnamed)
        9
        2
        4 5 6 0 0 0 1 1 1
        0 0 0 0 0
        14 15 16 0 0 0 1 1 1
        20 1 0 0 0
        PivotPoint 1 2 3
        ParentObject 1
        """.utf8)
    }
    static func buildingAssets(scale: String? = nil, looping: String? = nil) -> [Asset] {
        [Asset(path: directory + "/DepotCustom.ae", bytes: definition(scale: scale, looping: looping)),
         Asset(path: scenePath, bytes: scene()),
         Asset(path: meshPath, bytes: mesh()),
         Asset(path: directory + "/Body.uv", bytes: uv)]
    }
    static func resourceAssets() -> [Asset] {
        [Asset(path: "Fixture/Resources/Crystal.lwo", bytes: mesh(size: 2)),
         Asset(path: "Fixture/Resources/Ore.lwo", bytes: mesh(size: 3)),
         Asset(path: "Fixture/Resources/Stud.LWO", bytes: mesh(size: 4))]
    }
}

@main struct OriginalMissionObjectModelTests {
    private typealias F = MissionObjectFixture

    static func main() throws {
        try resourceMapping()
        try standOnlyBuilding()
        try scaleAndLooping()
        try componentPriority()
        try diagnostics()
        visibility()
        #if os(macOS)
        try sceneKitIntegration()
        #endif
        print("PASS: synthetic original mission-object mapping, stand-only AE, Scale/LOOPING, component priority, diagnostics and reveal visibility")
    }

    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00001 }
    static func expectFailure(_ fragments: [String], _ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected failure containing \(fragments)")
        } catch {
            let message = String(describing: error)
            for fragment in fragments {
                precondition(message.localizedCaseInsensitiveContains(fragment),
                             "Expected '\(fragment)' in diagnostic '\(message)'")
            }
        }
    }

    static func resourceMapping() throws {
        let config = try F.config()
        let resources = try F.resources(F.resourceAssets())
        for (type, suffix, size, isCrystal) in [
            ("pOwErCrYsTaL", "Crystal.lwo", 2.0, true),
            ("oRE", "Ore.lwo", 3.0, false),
            ("pRoCeSsEdOrE", "Stud.LWO", 4.0, false)
        ] {
            let asset = try OriginalMissionObjectAsset.load(type: type, config: config, resources: resources)
            guard case .resource(let mesh, let color) = asset.contents else {
                preconditionFailure("Resource \(type) was classified as building")
            }
            precondition(mesh.path == "Fixture/Resources/" + suffix)
            precondition(Double(mesh.mesh.vertices[1].x) == size && asset.scale == 1)
            precondition((color != nil) == isCrystal)
            if let color {
                precondition(near(color.red, 32 / 255.0) && near(color.green, 128 / 255.0) && near(color.blue, 224 / 255.0))
            }
        }
        // An explicit LWO extension is accepted without producing .lwo.lwo.
        let explicit = try F.config(crystal: "Fixture/Resources/Crystal.lwo")
        let asset = try OriginalMissionObjectAsset.load(type: "PowerCrystal", config: explicit, resources: resources)
        guard case .resource(let mesh, _) = asset.contents else { preconditionFailure("Expected LWO") }
        precondition(mesh.path == "Fixture/Resources/Crystal.lwo")
    }

    static func standOnlyBuilding() throws {
        let config = try F.config(directory: "Fixture\\DepotCustom\\")
        let resources = try F.resources(F.buildingAssets(scale: "2.5"))
        // This arbitrary configured type proves the renderer isn't a hardcoded
        // Toolstation path, while the actual OL Toolstation name is also covered.
        for type in ["sEcReThUb", "tOoLsTaTiOn"] {
            let asset = try OriginalMissionObjectAsset.load(type: type, config: config, resources: resources)
            guard case .building(let clip) = asset.contents else { preconditionFailure("Expected building") }
            precondition(asset.scale == 2.5)
            precondition(clip.path == F.scenePath && clip.looping)
            precondition(clip.scene.objects.count == 2 && clip.components.count == 2)
            precondition(clip.components[0] == nil)
            precondition(clip.components[1]?.path == F.meshPath)
            precondition(clip.components[1]?.uvMap?.corners[0].count == 4)
            precondition(clip.scene.objects[1].parentIndex == 1)
            precondition(clip.scene.objects[1].pivot == [1, 2, 3])
        }
        let activities = try OriginalModelActivities.load(directory: F.directory, resources: resources,
                                                           sharedObjects: "Fixture/Shared")
        expectFailure(["Activity_Route", F.directory]) { _ = try activities.activity("Activity_Route") }
    }

    static func scaleAndLooping() throws {
        for (raw, expected) in [(nil, 1.0), ("0", 1.0), ("2.5", 2.5), ("-2", -2.0)] as [(String?, Double)] {
            let activities = try OriginalModelActivities(directory: F.directory,
                definition: LegoConfig(data: F.definition(scale: raw)))
            precondition(activities.scale == expected)
        }
        for raw in ["nan", "inf", "oops", "1e100"] {
            expectFailure(["Scale"]) {
                _ = try OriginalModelActivities(directory: F.directory,
                    definition: LegoConfig(data: F.definition(scale: raw)))
            }
        }
        for (raw, looping) in [(nil, true), ("TRUE", true), ("YES", true), ("on", true),
                               ("FALSE", false), ("no", false), ("Off", false),
                               ("0", true), ("1", true), ("unknown", true)] as [(String?, Bool)] {
            let resources = try F.resources(F.buildingAssets(looping: raw))
            let activities = try OriginalModelActivities.load(directory: F.directory,
                resources: resources, sharedObjects: nil)
            let clip = try OriginalLightWaveClipAsset.load(activities: activities,
                activity: "Activity_Stand", resources: resources)
            precondition(clip.looping == looping && clip.scene.firstFrame == 4)
            precondition(clip.frame(elapsed: -1) == 0 && clip.frame(elapsed: 0) == 0)
            precondition(clip.frame(elapsed: 0.5) == 5)
            precondition(clip.frame(elapsed: 2) == (looping ? 0 : 20))
            precondition(clip.frame(elapsed: 2.5) == (looping ? 5 : 20))
            precondition(clip.duration == 2)
        }
        let zeroScene = try LightWaveScene(data: F.scene(first: 0, last: 0))
        let clip = OriginalLightWaveClipAsset(path: F.scenePath, scene: zeroScene, components: [], looping: true)
        precondition(clip.frame(elapsed: 1_000) == 0 && clip.duration == 0.1)
    }

    static func componentPriority() throws {
        let config = try F.config()
        let base = F.buildingAssets().filter { $0.path != F.meshPath && !$0.path.hasSuffix(".uv") }
        let local = F.Asset(path: F.meshPath, bytes: F.mesh(size: 1))
        let shared = F.Asset(path: F.sharedMeshPath, bytes: F.mesh(size: 9))
        let author = F.Asset(path: "Author/Body.lwo", bytes: F.mesh(size: 99))
        func component(_ resources: GameResources) throws -> OriginalLightWaveMeshAsset {
            let asset = try OriginalMissionObjectAsset.load(type: "Toolstation", config: config, resources: resources)
            guard case .building(let clip) = asset.contents, let mesh = clip.components[1] else {
                preconditionFailure("Expected configured component")
            }
            return mesh
        }
        let localFirst = try GameResources(archives: [(0, F.wad(base + [local])), (1, F.wad([shared, author]))])
        let selected = try component(localFirst)
        precondition(selected.path == F.meshPath && selected.mesh.vertices[1].x == 1)
        let override = F.Asset(path: F.meshPath.uppercased(), bytes: F.mesh(size: 2))
        let overriding = try GameResources(archives: [(0, F.wad(base + [local])), (1, F.wad([shared, override]))])
        let overridden = try component(overriding)
        precondition(overridden.path == F.meshPath && overridden.mesh.vertices[1].x == 2)
        let fallback = try component(F.resources(base + [shared, author]))
        precondition(fallback.path == F.sharedMeshPath && fallback.mesh.vertices[1].x == 9)
        let missing = try F.resources(base + [author])
        expectFailure(["missing component", "Body.lwo", F.meshPath, F.sharedMeshPath]) { _ = try component(missing) }
        let corrupt = F.Asset(path: F.meshPath, bytes: Data([0, 1, 2]))
        let invalid = try F.resources(base + [corrupt, shared])
        expectFailure(["LightWave"]) { _ = try component(invalid) }
        // A corrupt selected local component must not silently use valid shared art.
        let compressed = F.Asset(path: F.meshPath, bytes: F.mesh(), flags: 3)
        let unreadable = try F.resources(base + [compressed, shared])
        expectFailure(["compress"]) { _ = try component(unreadable) }
    }

    static func diagnostics() throws {
        let config = try F.config()
        let resources = try F.resources(F.resourceAssets())
        expectFailure(["unsupported OL type", "VehicleNotPorted"]) {
            _ = try OriginalMissionObjectAsset.load(type: "VehicleNotPorted", config: config, resources: resources)
        }
        expectFailure(["DepotCustom.ae"]) {
            _ = try OriginalMissionObjectAsset.load(type: "Toolstation", config: config, resources: resources)
        }
        let missingScene = try F.resources([F.Asset(path: F.directory + "/DepotCustom.ae", bytes: F.definition())])
        expectFailure([F.scenePath]) {
            _ = try OriginalMissionObjectAsset.load(type: "Toolstation", config: config, resources: missingScene)
        }
        let noMisc = try LegoConfig(text: "Lego* { Main { Value fixture } }")
        expectFailure(["MiscObjects::Ore"]) {
            _ = try OriginalMissionObjectAsset.load(type: "Ore", config: noMisc, resources: resources)
        }
        let missingOre = try F.resources([])
        expectFailure(["Fixture/Resources/Ore.lwo"]) {
            _ = try OriginalMissionObjectAsset.load(type: "Ore", config: config, resources: missingOre)
        }
        let xOnly = try F.resources([F.Asset(path: "Fixture/Resources/Ore.x", bytes: Data("unimplemented DirectX".utf8))])
        expectFailure(["Ore.lwo", "Ore.x", "unsupported DirectX"]) {
            _ = try OriginalMissionObjectAsset.load(type: "Ore", config: config, resources: xOnly)
        }
        let corruptWithX = try F.resources([
            F.Asset(path: "Fixture/Resources/Ore.lwo", bytes: Data("invalid".utf8)),
            F.Asset(path: "Fixture/Resources/Ore.x", bytes: Data("fallback".utf8))
        ])
        expectFailure(["LightWave", "Ore.x", "unsupported DirectX"]) {
            _ = try OriginalMissionObjectAsset.load(type: "Ore", config: config, resources: corruptWithX)
        }
        let explicitX = try F.config(crystal: "Fixture/Resources/Crystal.x")
        expectFailure(["DirectX .x", "Crystal.x"]) {
            _ = try OriginalMissionObjectAsset.load(type: "PowerCrystal", config: explicitX, resources: resources)
        }
        for value in [nil, "32:128", "-1:128:224", "32:128:256", "nan:128:224", "32::224", "1:2:bad:3", "1:2:3:4"] as [String?] {
            let invalid = try F.config(color: value)
            expectFailure(["PowerCrystalRGB"]) {
                _ = try OriginalMissionObjectAsset.load(type: "PowerCrystal", config: invalid, resources: resources)
            }
        }
        let unsafe = try F.config(crystal: "../Crystal")
        expectFailure(["unsafe", "MiscObjects::Crystal"]) {
            _ = try OriginalMissionObjectAsset.load(type: "PowerCrystal", config: unsafe, resources: resources)
        }
        for lws in ["FALSE", "0", "1"] {
            let activities = try OriginalModelActivities(directory: F.directory,
                definition: LegoConfig(data: F.definition(lws: lws)))
            expectFailure(["LWSFILE TRUE required"]) { _ = try activities.activity("Activity_Stand") }
        }
    }

    static func visibility() {
        // Initial load, diagnostic toggles and excavation refresh share this
        // same policy: an exposed original model never depends on debug spheres.
        for markers in [false, true] {
            for isRaider in [false, true] {
                for originalModel in [false, true] {
                    precondition(OriginalObjectVisibility.isHidden(discovered: false, isRockRaider: isRaider,
                        hasOriginalModel: originalModel, showObjectMarkers: markers))
                    precondition(OriginalObjectVisibility.isHidden(discovered: true, isRockRaider: isRaider,
                        hasOriginalModel: originalModel, showObjectMarkers: markers, isFirstPersonBody: true))
                    let hidden = OriginalObjectVisibility.isHidden(discovered: true, isRockRaider: isRaider,
                        hasOriginalModel: originalModel, showObjectMarkers: markers)
                    precondition(hidden == (!isRaider && !originalModel && !markers))
                }
            }
        }
    }

    #if os(macOS)
    static func sceneKitIntegration() throws {
        let config = try F.config()
        let resources = try F.resources(F.buildingAssets(scale: "2.5") + F.resourceAssets())
        let building = try OriginalMissionObjectAsset.load(type: "Toolstation", config: config, resources: resources)
        let model = try OriginalMissionObjectModel(asset: building, resources: resources, blockSize: 40, sharedTextures: nil)
        precondition(near(Double(model.root.scale.x), 2.5 / 40))
        precondition(model.root.position.x == 0 && model.root.position.y == 0 && model.root.position.z == 0,
                     "Original origin must not inherit proxy capsule/sphere height")
        precondition(model.root.geometry == nil && model.root.childNodes.count == 1)
        guard case .building(let source) = building.contents else { preconditionFailure("Expected building") }
        let clip = OriginalLightWaveRenderer.Clip(asset: source, resources: resources, sharedTextures: nil)
        precondition(clip.root.childNodes.count == 1 && clip.parts[0].geometry == nil)
        precondition(clip.parts[1].parent === clip.parts[0])
        // Clip construction applies frame zero immediately, before any timer tick.
        precondition(near(Double(clip.parts[1].transform.m41), 3) &&
                     near(Double(clip.parts[1].transform.m42), 3) &&
                     near(Double(clip.parts[1].transform.m43), 3), "Pivot must be applied before placement")
        clip.update(elapsed: 1)
        precondition(near(Double(clip.parts[1].transform.m41), 8))
        clip.update(elapsed: 2)
        precondition(near(Double(clip.parts[1].transform.m41), 3), "Stand clip must loop")
        guard let geometry = clip.parts[1].geometry else { preconditionFailure("Missing original geometry") }
        precondition(geometry.elements.count == 1 && geometry.elements[0].primitiveCount == 2)
        precondition(geometry.sources(for: .vertex).first?.vectorCount == 4)
        precondition(geometry.sources(for: .texcoord).first?.vectorCount == 4,
                     "Shared renderer must retain original corner UV source")
        precondition(geometry.materials.count == 1)
        // Raider shares exactly the same geometry pipeline, but retains its
        // activity switching and hit-node-to-original-OL-anchor selection.
        let raiderDefinition = try LegoConfig(text: """
        Lego* {
          Scale 2.5
          Activities {
            Activity_Stand Idle
            Activity_Route Idle
          }
          Idle {
            FILE Waiting
            LWSFILE TRUE
          }
        }
        """)
        let activities = try OriginalRaiderActivities(directory: F.directory, definition: raiderDefinition)
        let raider = try OriginalRaiderModel(activities: activities, resources: resources, blockSize: 40)
        let anchor = SCNNode()
        anchor.name = "Original OL: Object17 / Pilot"
        anchor.position = SCNVector3(12, 3.25, -7)
        anchor.addChildNode(raider.root)
        precondition(raider.root.position.y == 0 && near(Double(raider.root.scale.x), 2.5 / 40))
        let standRoot = raider.root.childNodes[0], routeRoot = raider.root.childNodes[1]
        let standMesh = standRoot.childNodes[0].childNodes[0]
        precondition(standMesh.geometry != nil && near(Double(standMesh.transform.m42), 3),
                     "Raider Stand is initialized at frame zero, with original pivot")
        precondition(!standRoot.isHidden && routeRoot.isHidden)
        let anchors = ["Object17": anchor]
        precondition(OriginalObjectPresentation.placementIdentifier(containing: standMesh, anchors: anchors) == "Object17")
        precondition(OriginalObjectPresentation.placementIdentifier(containing: SCNNode(), anchors: anchors) == nil)
        raider.setMoving(true)
        precondition(standRoot.isHidden && !routeRoot.isHidden)
        let routeMesh = routeRoot.childNodes[0].childNodes[0]
        precondition(OriginalObjectPresentation.placementIdentifier(containing: routeMesh, anchors: anchors) == "Object17")
        raider.setMoving(false)
        precondition(!standRoot.isHidden && routeRoot.isHidden)
        let eye = OriginalObjectPresentation.eyePosition(above: anchor.position)
        precondition(eye.x == anchor.position.x && eye.z == anchor.position.z)
        precondition(near(Double(eye.y), 3.25 + 0.48 + 0.20), "Ground anchors must preserve original native eye height")
        let proxy = SCNNode(geometry: SCNCapsule(capRadius: 0.22, height: 0.80))
        proxy.position.y = OriginalObjectPresentation.diagnosticCenterHeight
        anchor.addChildNode(proxy)
        precondition(near(Double(proxy.worldPosition.y), 3.25 + 0.48))
        precondition(OriginalObjectPresentation.placementIdentifier(containing: proxy, anchors: anchors) == "Object17")

        let crystal = try OriginalMissionObjectAsset.load(type: "PowerCrystal", config: config, resources: resources)
        let crystalModel = try OriginalMissionObjectModel(asset: crystal, resources: resources, blockSize: 40, sharedTextures: nil)
        precondition(near(Double(crystalModel.root.scale.x), 1 / 40.0) && crystalModel.root.position.y == 0)
        guard let crystalGeometry = crystalModel.root.childNodes.first?.geometry else {
            preconditionFailure("Resource must have real LWOB geometry")
        }
        for material in crystalGeometry.materials {
            guard let diffuse = material.diffuse.contents as? NSColor,
                  let emissive = material.emission.contents as? NSColor else {
                preconditionFailure("Crystal must apply configured diffuse and emissive color")
            }
            for color in [diffuse, emissive] {
                precondition(near(Double(color.redComponent), 32 / 255.0))
                precondition(near(Double(color.greenComponent), 128 / 255.0))
                precondition(near(Double(color.blueComponent), 224 / 255.0))
            }
        }
        for size in [0.0, -1.0, Double.nan, Double.infinity] {
            expectFailure(["BlockSize"]) {
                _ = try OriginalMissionObjectModel(asset: crystal, resources: resources, blockSize: size, sharedTextures: nil)
            }
        }
        print("PASS: SceneKit original mission-object scale/origin, hierarchy/pivot, corner UVs and crystal materials")
    }
    #endif
}
