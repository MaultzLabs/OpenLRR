import Foundation

private func word(_ v: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
     UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
}
private func syntheticWad(_ files: [(String, [UInt8])]) -> Data {
    var bytes = [UInt8]([87, 87, 65, 68]) + word(UInt32(files.count))
    for (name, _) in files { bytes += Array(name.utf8) + [0] }
    for (name, _) in files { bytes += Array(("C:\\Original\\" + name).utf8) + [0] }
    var offset = bytes.count + files.count * 16
    for (_, payload) in files {
        bytes += word(1) + word(UInt32(payload.count)) +
                 word(UInt32(payload.count)) + word(UInt32(offset))
        offset += payload.count
    }
    for (_, payload) in files { bytes += payload }
    return Data(bytes)
}
private func syntheticMap(_ values: [UInt16], width: UInt32, height: UInt32) -> [UInt8] {
    var bytes: [UInt8] = [77, 65, 80, 32]
    bytes += word(8 + UInt32(values.count * 2))
    bytes += word(width)
    bytes += word(height)
    for value in values {
        bytes += [UInt8(truncatingIfNeeded: value),
                  UInt8(truncatingIfNeeded: value >> 8)]
    }
    return bytes
}

@main struct LevelRuntimeResourcesTests {
    static func main() throws {
        let cfg = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              FullName Driller_Night
              TerrainMap Levels\\GameLevels\\Level01\\Surf.map
              PredugMap Levels\\GameLevels\\Level01\\Dugg.map
              SurfaceMap Levels\\GameLevels\\Level01\\High.map
              OListFile Levels\\GameLevels\\Level01\\Objects.ol
              NERPFile Levels\\GameLevels\\Level01\\Level01.npl
              NextLevel Levels::Level02
            }
          }
        }
        """)
        let manifest = try LevelRuntimeResources(config: cfg, identifier: "Levels::Level01")
        precondition(manifest.title == "Driller Night")
        precondition(manifest.mapPaths.count == 3)
        precondition(manifest.objectListPath?.hasSuffix("Objects.ol") == true)
        precondition(manifest.scriptPath?.hasSuffix("Level01.npl") == true)
        precondition(manifest.nextLevel == "Levels::Level02")

        let first = syntheticMap([0, 4, 9, 5], width: 2, height: 2)
        let exposed = syntheticMap([0, 1, 2, 1], width: 2, height: 2)
        let height = syntheticMap([1, 1, 2, 2], width: 2, height: 2)
        let wad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map", first),
            ("Levels\\GameLevels\\Level01\\Dugg.map", exposed),
            ("Levels\\GameLevels\\Level01\\High.map", height)
        ])
        let archive = try GameResources(archives: [(0, wad)])
        let maps = try manifest.loadMaps(resources: archive)
        precondition(maps.count == 3)
        precondition(maps["TerrainMap"]?.value(x: 1, y: 0) == 4)
        precondition(maps["PredugMap"]?.value(x: 0, y: 1) == 2)
        precondition(maps["SurfaceMap"]?.value(x: 1, y: 1) == 2)

        // Native level scene: MAP dimensions include a border vertex.
        let world = try LevelWorld(manifest: manifest, resources: archive)
        precondition(world.identifier == "Levels::Level01")
        precondition(world.width == 1 && world.height == 1)
        precondition(world.tile(x: 0, y: 0)?.terrain.rawValue == "Tunnel")
        precondition(world.tile(x: 0, y: 0)?.excavation.rawValue == "Wall")
        precondition(world.tile(x: 1, y: 0) == nil)
        precondition(world.tile(x: -1, y: 0) == nil)

        // Multi-tile map with an exposed cavern and a crystal wall.
        let nativeTerrain = syntheticMap([1, 4, 2,
                                          2, 10, 3,
                                          1, 2, 4], width: 3, height: 3)
        let nativePredug = syntheticMap([0, 1, 0,
                                         0, 2, 0,
                                         0, 0, 0], width: 3, height: 3)
        let nativeSurface = syntheticMap([1, 3, 3,
                                          1, 1, 5,
                                          1, 1, 2], width: 3, height: 3)
        let nativeWad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map", nativeTerrain),
            ("Levels\\GameLevels\\Level01\\Dugg.map", nativePredug),
            ("Levels\\GameLevels\\Level01\\High.map", nativeSurface)
        ])
        let nativeResources = try GameResources(archives: [(0, nativeWad)])
        let nativeWorld = try LevelWorld(manifest: manifest, resources: nativeResources)
        precondition(nativeWorld.width == 2 && nativeWorld.height == 2)
        precondition(nativeWorld.tile(x: 1, y: 0)?.terrain.rawValue == "Dirt")
        precondition(nativeWorld.tile(x: 1, y: 0)?.excavation.isCavern == true)
        precondition(nativeWorld.tile(x: 1, y: 1)?.terrain.rawValue == "Energy crystal seam")
        precondition(nativeWorld.tile(x: 1, y: 1)?.excavation.rawValue == "Hidden cavern")
        precondition(nativeWorld.initialCameraTile.x == 1 &&
                     nativeWorld.initialCameraTile.y == 0)
        // Genuine MAP-derived 3D geometry with no external assets or game
        // semantics invented by a renderer.
        let mesh = try NativeTerrainMesh(world: nativeWorld)
        precondition(mesh.tileCount == 4)
        precondition(mesh.triangleCount > 8)  // four tile tops + exposed wall sides
        precondition(mesh.surfaces.contains { $0.material == .crystal })
        precondition(mesh.surfaces.contains { $0.material == .wallFace })
        precondition(mesh.surfaces.allSatisfy {
            $0.vertices.count == $0.normals.count && $0.vertices.count % 3 == 0
        })
        precondition(mesh.surfaces.flatMap(\\.normals).allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        })
        precondition(mesh.surfaces.flatMap(\\.vertices).contains {
            $0.y > NativeTerrainMesh.previewWallHeight
        })
        do {
            _ = try NativeTerrainMesh(world: nativeWorld, maxTiles: 3)
            preconditionFailure("Tile-count memory guard was bypassed")
        } catch is NativeTerrainMesh.MeshError {}

        // Correctness of raw terrain IDs is anchored in
        // game/GameCommon.h::Lego_SurfaceType.
        precondition(LevelWorld.Terrain(code: 1) == .immovable)
        precondition(LevelWorld.Terrain(code: 3) == .medium)
        precondition(LevelWorld.Terrain(code: 7) == .water)
        precondition(LevelWorld.Terrain(code: 9) == .lake)
        precondition(LevelWorld.Terrain(code: 10) == .crystalSeam)
        precondition(LevelWorld.Terrain(code: 18) == .unknown)
        let wrongHeight = syntheticMap([1, 2, 3, 4], width: 2, height: 2)
        let inconsistentWad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map", nativeTerrain),
            ("Levels\\GameLevels\\Level01\\Dugg.map", nativePredug),
            ("Levels\\GameLevels\\Level01\\High.map", wrongHeight)
        ])
        do {
            _ = try LevelWorld(manifest: manifest,
                               resources: GameResources(archives: [(0, inconsistentWad)]))
            preconditionFailure("Mismatched map dimensions were accepted")
        } catch is LevelWorld.WorldError {}

        do {
            _ = try LevelRuntimeResources(config: cfg, identifier: "Main::Other")
            preconditionFailure("non-level identifier was accepted")
        } catch is LevelRuntimeResources.RuntimeError {}
        let unsafe = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              TerrainMap ..\\secret.map
            }
          }
        }
        """)
        do {
            _ = try LevelRuntimeResources(config: unsafe, identifier: "Levels::Level01")
            preconditionFailure("unsafe original level resource path was accepted")
        } catch is LevelRuntimeResources.RuntimeError {}

        print("PASS: authentic level map paths, native 16-bit decoding, and unsafe path rejection")
    }
}
