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
              TextureSet World\\WorldTextures\\RockSplit\\Rock:0:0
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
        // TextureSet contains retail ':' fields and must never pass through
        // relative-file path validation (regression: mission loading crash).
        precondition(manifest.textureSetSetting?.contains(":0:0") == true)
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
        // The original Map3D chooses the least-distorted diagonal from
        // four height samples, rather than using one diagonal for all tiles.
        precondition(NativeTerrainMesh.usesUpperLeftDiagonal(
            topLeft: 1, topRight: 9, bottomLeft: 2, bottomRight: 1))
        precondition(!NativeTerrainMesh.usesUpperLeftDiagonal(
            topLeft: 1, topRight: 1, bottomLeft: 2, bottomRight: 2))
        precondition(!NativeTerrainMesh.usesUpperLeftDiagonal(
            topLeft: 4, topRight: 4, bottomLeft: 4, bottomRight: 4))

        let triangleWad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map",
             syntheticMap([0, 0, 0, 0], width: 2, height: 2)),
            ("Levels\\GameLevels\\Level01\\Dugg.map",
             syntheticMap([1, 1, 1, 1], width: 2, height: 2)),
            ("Levels\\GameLevels\\Level01\\High.map",
             syntheticMap([1, 9, 2, 1], width: 2, height: 2))
        ])
        let triangleWorld = try LevelWorld(
            manifest: manifest,
            resources: GameResources(archives: [(0, triangleWad)]))
        let triangleMesh = try NativeTerrainMesh(world: triangleWorld)
        guard let floor = triangleMesh.surfaces.first(where: {
            $0.material == .cavernFloor
        }) else {
            preconditionFailure("Missing original cave floor triangles")
        }
        precondition(floor.vertices.count == 6)
        // Adaptive diagonal spans a(-0.5,-0.5) to d(+0.5,+0.5).
        precondition(floor.vertices[0].x == floor.vertices[3].x &&
                     floor.vertices[0].z == floor.vertices[3].z)
        precondition(floor.vertices[2].x == floor.vertices[4].x &&
                     floor.vertices[2].z == floor.vertices[4].z)
        precondition(floor.normals.allSatisfy { $0.y > 0.5 })

        // Original high.map triangulation must also govern object and camera
        // elevations: bilinear sampling diverges on non-coplanar quads.
        // This synthetic tile selects the upper-left/lower-right diagonal.
        precondition(abs((triangleWorld.elevation(atX: 0.75, y: 0.25) ?? -1)
                         - 5.0) < 0.0001)
        precondition(abs((triangleWorld.elevation(atX: 0.25, y: 0.75) ?? -1)
                         - 1.5) < 0.0001)
        precondition(triangleWorld.elevation(atX: 0.5, y: 0.5) == 1)
        precondition(triangleWorld.elevation(atX: 1, y: 1) == 1)
        precondition(triangleWorld.elevation(atX: -0.1, y: 0.5) == nil)
        precondition(triangleWorld.elevation(atX: .infinity, y: 0.5) == nil)

        // Opposite diagonal (b--c), including both triangle halves and
        // the right/bottom MAP border vertices.
        let defaultDiagonalWad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map",
             syntheticMap([0, 0, 0, 0], width: 2, height: 2)),
            ("Levels\\GameLevels\\Level01\\Dugg.map",
             syntheticMap([1, 1, 1, 1], width: 2, height: 2)),
            ("Levels\\GameLevels\\Level01\\High.map",
             syntheticMap([1, 1, 2, 9], width: 2, height: 2))
        ])
        let defaultWorld = try LevelWorld(
            manifest: manifest,
            resources: GameResources(archives: [(0, defaultDiagonalWad)]))
        precondition(defaultWorld.elevation(atX: 0.25, y: 0.25) == 1.25)
        precondition(defaultWorld.elevation(atX: 0.75, y: 0.75) == 5.25)
        precondition(defaultWorld.elevation(atX: 1, y: 0) == 1)
        precondition(defaultWorld.elevation(atX: 0, y: 1) == 2)


        precondition(mesh.triangleCount > 8)  // four tile tops + exposed wall sides
        precondition(mesh.surfaces.contains { $0.material == .crystal })
        precondition(mesh.surfaces.contains { $0.material == .wallFace })
        precondition(mesh.surfaces.allSatisfy {
            $0.vertices.count == $0.normals.count && $0.vertices.count % 3 == 0
        })
        precondition(mesh.surfaces.flatMap(\.normals).allSatisfy {
            $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
        })
        precondition(mesh.surfaces.flatMap(\.vertices).contains {
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
        // A corridor around original predug walls, with lava impassable.
        let corridor: [UInt16] = [
            1, 1, 1, 0, 0,
            0, 0, 1, 0, 0,
            1, 1, 1, 0, 0,
            1, 0, 1, 1, 0,
            0, 0, 0, 0, 0
        ]
        var surfaces = [UInt16](repeating: 4, count: 25)
        surfaces[1] = 6  // Lava blocks the shortcut east of (0,0).
        let terrainData = syntheticMap(surfaces, width: 5, height: 5)
        let predugData = syntheticMap(corridor, width: 5, height: 5)
        let highData = syntheticMap([UInt16](repeating: 2, count: 25),
                                    width: 5, height: 5)
        let pathWad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map", terrainData),
            ("Levels\\GameLevels\\Level01\\Dugg.map", predugData),
            ("Levels\\GameLevels\\Level01\\High.map", highData)
        ])
        let corridorWorld = try LevelWorld(
            manifest: manifest, resources: GameResources(archives: [(0, pathWad)]))
        let routing = NativeLevelNavigation(world: corridorWorld)
        let origin = NativeLevelNavigation.Position(x: 2, y: 0)
        let destination = NativeLevelNavigation.Position(x: 0, y: 2)
        precondition(routing.route(from: origin, to: destination) == [
            origin,
            NativeLevelNavigation.Position(x: 2, y: 1),
            NativeLevelNavigation.Position(x: 2, y: 2),
            NativeLevelNavigation.Position(x: 1, y: 2),
            destination
        ])
        precondition(routing.route(from: origin, to: origin) == [origin])
        precondition(routing.route(from: NativeLevelNavigation.Position(x: 0, y: 0),
                                   to: destination) == nil)
        precondition(!routing.canWalk(NativeLevelNavigation.Position(x: 1, y: 0)))
        precondition(!routing.canWalk(NativeLevelNavigation.Position(x: -1, y: 0)))
        precondition(routing.route(from: origin,
                                   to: NativeLevelNavigation.Position(x: 1, y: 0)) == nil)
        precondition(NativeLevelNavigation(world: corridorWorld, maximumTiles: 10)
                      .route(from: origin, to: destination) == nil)

        // Native mining orders must reach a real cardinally adjacent cavern
        // before a mineable wall becomes floor. WAD and MAP bytes stay intact.
        let mining = NativeExcavationState(world: corridorWorld)
        let wall = NativeLevelNavigation.Position(x: 1, y: 1)
        precondition(mining.canDrill(wall))
        precondition(!mining.canDrill(origin)) // exposed cavern is not a wall
        precondition(!mining.canDrill(.init(x: -1, y: 1)))
        guard let order = mining.plan(from: origin, wall: wall) else {
            preconditionFailure("Expected accessible drilling face")
        }
        precondition(order.approach == .init(x: 2, y: 1))
        precondition(order.route == [origin, order.approach])
        precondition(!mining.finish(order, raiderAt: origin))
        precondition(mining.excavated.isEmpty)
        precondition(mining.finish(order, raiderAt: order.approach))
        precondition(!mining.finish(order, raiderAt: order.approach))
        precondition(!mining.canDrill(wall))
        precondition(mining.tile(x: 1, y: 1)?.terrain == .tunnel)
        precondition(mining.tile(x: 1, y: 1)?.excavation == .exposed)
        precondition(corridorWorld.tile(x: 1, y: 1)?.excavation == .wall)
        precondition(NativeLevelNavigation(world: corridorWorld,
                     excavated: mining.excavated).canWalk(wall))
        precondition(NativeLevelNavigation(world: corridorWorld).route(
                     from: order.approach, to: wall) == nil)
        precondition(NativeLevelNavigation(world: corridorWorld,
                     excavated: mining.excavated).route(
                     from: order.approach, to: wall) == [order.approach, wall])
        let dugMesh = try NativeTerrainMesh(world: corridorWorld,
                                            excavatedTiles: mining.excavated)
        precondition(dugMesh.triangleCount > 0)
        precondition(dugMesh.surfaces.contains { $0.material == .cavernFloor })
        precondition(mining.plan(from: origin, wall: wall) == nil)

        // Source-grounded original BMP world atlas paths. A synthetic WAD
        // tests lookup without redistributing a copyrighted actual image.
        let textureWad = syntheticWad([
            ("World\\WorldTextures\\RockSplit\\Rock00.BMP", [66,77,1,1]),
            ("World\\WorldTextures\\RockSplit\\Rock02.BMP", [66,77,2,2]),
            ("World\\WorldTextures\\RockSplit\\Rock40.BMP", [66,77,3,3]),
            ("World\\WorldTextures\\IceSplit\\ICE00.BMP", [66,77,4,4])
        ])
        let textureResources = try GameResources(archives: [(0,textureWad)])
        guard let rockTextures = OriginalTerrainTextureCatalog(
            textureSetSetting: "Rock", resources: textureResources) else {
            preconditionFailure("Original Rock atlas was not discovered")
        }
        precondition(rockTextures.family == .rock)
        precondition(rockTextures.path(for: 0, resources: textureResources)?
            .lowercased().hasSuffix("rock00.bmp") == true)
        precondition(rockTextures.bytes(for: 0x40, resources: textureResources) ==
                     Data([66,77,3,3]))
        precondition(rockTextures.path(for: 0x45, resources: textureResources) == nil)
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: "Ice", resources: textureResources)?.family == .ice)
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: "Lava", resources: textureResources) == nil)
        precondition(OriginalTerrainTextureCatalog.representativeID(
            for: .crystalSeam) == 0x20)

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
