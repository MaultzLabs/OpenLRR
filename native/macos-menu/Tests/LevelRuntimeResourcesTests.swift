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
        let referenced = try LegoConfig(text: """
        Lego* {
          Textures {
            Rock {
              TextureBaseName World\\WorldTextures\\RockSplit\\Rock
            }
          }
          Levels {
            Level01 {
              TextureSet Textures::Rock
            }
          }
        }
        """)
        let referencedLevel = try LevelRuntimeResources(config: referenced, identifier: "Levels::Level01")
        precondition(referencedLevel.textureSetSetting == "World\\WorldTextures\\RockSplit\\Rock")
        let missingReference = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              TextureSet Textures::Missing
            }
          }
        }
        """)
        do {
            _ = try LevelRuntimeResources(config: missingReference, identifier: "Levels::Level01")
            preconditionFailure("Missing reference must not choose a different biome")
        } catch LevelRuntimeResources.RuntimeError.invalid { }
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
              ObjectiveText Levels\\ObjectiveText.txt
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
        precondition(manifest.objectiveTextPath == "Levels\\ObjectiveText.txt")
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


        precondition(mesh.triangleCount == 8) // four shared-vertex tiles, no cube side faces
        precondition(mesh.surfaces.contains { $0.material == .crystal })
        precondition(!mesh.surfaces.contains { $0.material == .wallFace })
        precondition(mesh.surfaces.contains { surface in
            surface.material == .crystal && surface.normals.contains { $0.y > 0 && $0.y < 0.99 }
        })
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

        // Hidden areas reveal through the original eight-neighbour flood,
        // while separated cavities and liquid collision remain intact.
        var hiddenPredug = [UInt16](repeating: 0, count: 25)
        hiddenPredug[7] = 1
        hiddenPredug[5] = 2
        hiddenPredug[10] = 2
        hiddenPredug[18] = 2
        let hiddenResources = try GameResources(archives: [(0, syntheticWad([
            ("Levels/GameLevels/Level01/Surf.map", syntheticMap([UInt16](repeating: 4, count: 25), width: 5, height: 5)),
            ("Levels/GameLevels/Level01/Dugg.map", syntheticMap(hiddenPredug, width: 5, height: 5)),
            ("Levels/GameLevels/Level01/High.map", syntheticMap([UInt16](repeating: 0, count: 25), width: 5, height: 5))
        ]))])
        let hiddenWorld = try LevelWorld(manifest: manifest, resources: hiddenResources)
        let discovery = NativeExcavationState(world: hiddenWorld)
        let dig = discovery.plan(from: .init(x: 2, y: 1), wall: .init(x: 1, y: 1))!
        precondition(discovery.finish(dig, raiderAt: dig.approach))
        precondition(discovery.revealed == [.init(x: 0, y: 1), .init(x: 0, y: 2)])
        let revealedNav = NativeLevelNavigation(world: hiddenWorld, excavated: discovery.excavated, revealed: discovery.revealed)
        precondition(revealedNav.canWalk(.init(x: 0, y: 2)))
        precondition(!revealedNav.canWalk(.init(x: 3, y: 3)))
        let revealedMesh = try NativeTerrainMesh(world: hiddenWorld, excavatedTiles: discovery.excavated,
            revealedTiles: discovery.revealed, rubbleTiles: discovery.rubble)
        precondition(revealedMesh.surfaces.contains { $0.material == .rubble })

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
        var pointerCells = [UInt16](repeating: 0, count: 25)
        pointerCells[6] = 1 // wall (1,1)
        pointerCells[7] = 1 // exposed (2,1)
        pointerCells[24] = 1 // border vertex must not be enumerated
        let pointerConfig = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              TerrainMap Levels/GameLevels/Level01/Surf.map
              PredugMap Levels/GameLevels/Level01/Dugg.map
              SurfaceMap Levels/GameLevels/Level01/High.map
              BlockPointersMap Tuto.map
            }
          }
        }
        """)
        let pointerManifest = try LevelRuntimeResources(config: pointerConfig, identifier: "Levels::Level01")
        let pathWad = syntheticWad([
            ("Tuto.map", syntheticMap(pointerCells, width: 5, height: 5)),
            ("Levels\\GameLevels\\Level01\\Surf.map", terrainData),
            ("Levels\\GameLevels\\Level01\\Dugg.map", predugData),
            ("Levels\\GameLevels\\Level01\\High.map", highData)
        ])
        let corridorWorld = try LevelWorld(
            manifest: pointerManifest, resources: GameResources(archives: [(0, pathWad)]))
        precondition(corridorWorld.tutorialBlocks(1).count == 2)
        precondition(corridorWorld.tutorialBlocks(0).isEmpty)
        precondition(corridorWorld.tutorialBlocks(-1).isEmpty)
        precondition(corridorWorld.tutorialBlocks(256).isEmpty)
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
        // An original AE building's solid cell blocks pathfinding and the
        // same continuous clearance used by first-person input.
        let buildingCell = NativeLevelNavigation.Position(x: 2, y: 1)
        let withBuilding = NativeLevelNavigation(world: corridorWorld,
                                                  blockedBuildingTiles: [buildingCell])
        precondition(!withBuilding.canWalk(buildingCell))
        precondition(withBuilding.route(from: origin, to: buildingCell) == nil)
        precondition(!withBuilding.segmentIsClear(from: .init(x: 2.5, y: 0.5),
                                                 to: .init(x: 2.5, y: 1.5)))
        precondition(withBuilding.continuousRoute(from: .init(x: 2.5, y: 0.5),
                                                 to: .init(x: 2.5, y: 1.5)) == nil)
        precondition(routing.route(from: origin, to: origin) == [origin])
        precondition(routing.route(from: NativeLevelNavigation.Position(x: 0, y: 0),
                                   to: destination) == nil)
        precondition(!routing.canWalk(NativeLevelNavigation.Position(x: 1, y: 0)))
        precondition(!routing.canWalk(NativeLevelNavigation.Position(x: -1, y: 0)))
        precondition(routing.route(from: origin,
                                   to: NativeLevelNavigation.Position(x: 1, y: 0)) == nil)
        precondition(NativeLevelNavigation(world: corridorWorld, maximumTiles: 10)
                      .route(from: origin, to: destination) == nil)

        let preciseStart = NativeLevelNavigation.Point(x: 2.45, y: 0.55)
        let preciseGoal = NativeLevelNavigation.Point(x: 0.65, y: 2.6)
        let continuous = routing.continuousRoute(from: preciseStart, to: preciseGoal)!
        precondition(continuous.first == preciseStart && continuous.last == preciseGoal)
        precondition(continuous.count > 2) // A direct line would cut through rock.
        precondition(!routing.segmentIsClear(from: preciseStart, to: preciseGoal))
        for pair in zip(continuous, continuous.dropFirst()) {
            precondition(routing.segmentIsClear(from: pair.0, to: pair.1))
        }
        precondition(routing.continuousRoute(from: preciseStart,
            to: .init(x: 2.65, y: 0.65)) == [preciseStart, .init(x: 2.65, y: 0.65)])
        precondition(routing.continuousRoute(from: preciseStart,
            to: .init(x: 2.95, y: 1.5)) == nil) // Center fits; body would clip wall.
        precondition(!routing.segmentIsClear(from: .init(x: .nan, y: 1), to: preciseGoal))
        precondition(!routing.segmentIsClear(from: .init(x: 0.1, y: 2.5), to: preciseGoal))

        // First-person control uses the same discovered-cavern swept clearance
        // as click routing. These are synthetic map fixtures, not retail footage.
        let fpStart = NativeLevelNavigation.Point(x: 2.5, y: 0.5)
        var fp = NativeFirstPersonController(
            navigation: routing, position: fpStart, heading: 0)!
        precondition(fp.advance(forward: 1, turn: 0, elapsed: 0.1))
        precondition(abs(fp.position.y - 0.75) < 0.00001)
        precondition(fp.advance(forward: -1, turn: 0, elapsed: 0.1))
        precondition(abs(fp.position.y - fpStart.y) < 0.00001)
        precondition(!fp.advance(forward: 0, turn: 1, elapsed: 0.1))
        precondition(abs(fp.heading - 0.24) < 0.00001)
        let beforeInvalid = fp.heading
        precondition(!fp.advance(forward: 1, turn: 1, elapsed: .nan))
        precondition(fp.heading == beforeInvalid)
        precondition(!fp.advance(forward: .infinity, turn: 1, elapsed: 0.1))
        precondition(fp.heading == beforeInvalid)

        var wall = NativeFirstPersonController(
            navigation: routing, position: fpStart, heading: .pi / 2)!
        precondition(wall.advance(forward: 1, turn: 0, elapsed: 0.1))
        precondition(abs(wall.position.x - 2.75) < 0.00001)
        for _ in 0..<20 {
            precondition(!wall.advance(forward: 1, turn: 0, elapsed: 0.1))
        }
        precondition(wall.position.x < 2.77) // Expanded solid wall starts here.
        precondition(wall.advance(forward: -1, turn: 0, elapsed: 0.1))
        precondition(abs(wall.position.x - 2.5) < 0.00001)
        precondition(NativeFirstPersonController(
            navigation: routing, position: .init(x: 1.5, y: 0.5),
            heading: 0) == nil)
        precondition(NativeFirstPersonController(
            navigation: routing, position: fpStart, heading: .nan) == nil)
        var paused = NativeFirstPersonController(
            navigation: routing, position: fpStart, heading: 0)!
        precondition(paused.advance(forward: 1, turn: 0, elapsed: 50))
        precondition(abs(paused.position.y - 0.75) < 0.00001) // 100 ms cap

        // A second original OL Raider may stand on an otherwise open tile.
        // The static MAP clearance must not allow direct-control overlap.
        var occupied = NativeFirstPersonController(
            navigation: routing, position: fpStart, heading: 0)!
        let otherRaider = NativeDynamicCollision.Disc(
            center: .init(x: 2.5, y: 1.0),
            radius: NativeDynamicCollision.otherRaiderRadius)
        precondition(!occupied.advance(forward: 1, turn: 0, elapsed: 0.1,
                                       obstacles: [otherRaider]))
        precondition(occupied.position == fpStart)
        // Live positions are refreshed every frame; when the other Raider
        // moves away the identical input is no longer blocked.
        let movedAway = NativeDynamicCollision.Disc(
            center: .init(x: 2.5, y: 2.0),
            radius: NativeDynamicCollision.otherRaiderRadius)
        precondition(occupied.advance(forward: 1, turn: 0, elapsed: 0.1,
                                      obstacles: [movedAway]))
        precondition(abs(occupied.position.y - 0.75) < 0.00001)
        print("PASS: first-person steering, swept wall and live Raider clearance, reverse, turn and pause bounds")

        // Native mining orders must reach a real cardinally adjacent cavern
        // before a mineable wall becomes floor. WAD and MAP bytes stay intact.
        do {
        let mining = NativeExcavationState(world: corridorWorld)
        precondition(mining.tutorialGroundValue(1) == 8)
        precondition(mining.tutorialGroundValue(2) == 0)
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
        precondition(mining.tutorialGroundValue(1) == 16)
        precondition(mining.rubble.contains(order.wall))
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
        let openedNavigation = NativeLevelNavigation(world: corridorWorld, excavated: mining.excavated)
        let beforeMining = NativeLevelNavigation.Point(x: 2.5, y: 1.5)
        let openedFloor = NativeLevelNavigation.Point(x: 1.5, y: 1.5)
        precondition(!routing.segmentIsClear(from: beforeMining, to: openedFloor))
        precondition(openedNavigation.segmentIsClear(from: beforeMining, to: openedFloor))
        var minerFP = NativeFirstPersonController(navigation: routing, position: beforeMining, heading: -.pi / 2)!
        minerFP.navigation = openedNavigation
        for _ in 0..<4 { _ = minerFP.advance(forward: 1, turn: 0, elapsed: 0.1) }
        precondition(abs(minerFP.position.x - openedFloor.x) < 0.0001)
        let illegalOverlay = NativeLevelNavigation(world: corridorWorld, excavated: [.init(x: 1, y: 0)])
        precondition(!illegalOverlay.canWalk(.init(x: 1, y: 0)), "Excavation cannot turn lava into floor")
        }

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
