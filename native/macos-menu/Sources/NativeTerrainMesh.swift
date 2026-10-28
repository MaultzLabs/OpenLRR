import Foundation

/// Converts original Rock Raiders high.map, surf.map, and dugg.map into a
/// bounded, indexed 3D *debug* mesh. The geometry uses the original terrain
/// coordinates and elevations; its materials are provisional, not the retail
/// texture atlas. No changes are made to the game, WADs, or save files.
///
/// Ref: game/world/Map3D.h: one MAP vertex grid, one 3D block per adjacent
/// four vertices, and game/GameCommon.h terrain and predug values.
struct NativeTerrainMesh {
    enum MeshError: Error, CustomStringConvertible {
        case tooLarge(Int)
        var description: String {
            switch self {
            case .tooLarge(let count): return "3D preview exceeds safe tile limit (\(count))"
            }
        }
    }

    struct Point3 {
        let x: Float
        let y: Float
        let z: Float
    }

    enum Material: String, CaseIterable {
        case rubble
        case cavernFloor
        case hardRock
        case mediumRock
        case dirt
        case immovable
        case water
        case lava
        case ore
        case crystal
        case recharge
        case hidden
        case wallFace
    }

    struct Surface {
        let material: Material
        let vertices: [Point3]
        let normals: [Point3]

        var triangleCount: Int { vertices.count / 3 }
    }

    let surfaces: [Surface]
    let tileCount: Int
    let triangleCount: Int

    /// Retail Lego.cfg default level units (RRU config documentation):
    /// BlockSize 40; RoughLevel 6; DigDepth 40. We normalize block width
    /// to 1 in SceneKit so heights scale 6/40 and rock faces 40/40.
    /// Original Map3D roughness and roof details are still being ported.
    static let previewHeightScale: Float = 6.0 / 40.0
    static let previewWallHeight: Float = 40.0 / 40.0

    /// Original Map3D compares the two diagonals of the HIGH map at each
    /// block to select the less distorted triangulation. The "rotated"
    /// orientation joins upper-left to lower-right when that height
    /// difference is strictly smaller; equal differences retain the
    /// default upper-right/lower-left diagonal. This implementation is
    /// independent of D3DRM and the executable's fixed memory addresses.
    ///
    /// Reference for verification: Project Reversio's map3d.c
    /// (Map3D_Create and Map3D_SetBlockRotated); research reference only.
    static func usesUpperLeftDiagonal(
        topLeft: UInt16, topRight: UInt16,
        bottomLeft: UInt16, bottomRight: UInt16
    ) -> Bool {
        let cornerDifference = abs(Int(topLeft) - Int(bottomRight))
        let oppositeDifference = abs(Int(topRight) - Int(bottomLeft))
        return cornerDifference < oppositeDifference
    }

    init(world: LevelWorld, excavatedTiles: Set<NativeLevelNavigation.Position> = [], revealedTiles: Set<NativeLevelNavigation.Position> = [], rubbleTiles: Set<NativeLevelNavigation.Position> = [], maxTiles: Int = 150_000) throws {
        func wasExcavated(_ x: Int, _ y: Int) -> Bool {
            excavatedTiles.contains(.init(x: x, y: y)) &&
            world.tile(x: x, y: y)?.terrain.isMineableWall == true
        }
        let count = world.width * world.height
        guard count > 0 && count <= maxTiles else {
            throw MeshError.tooLarge(count)
        }

        struct Pending {
            var vertices: [Point3] = []
            var normals: [Point3] = []
        }
        var buckets: [Material: Pending] = [:]

        func addTriangle(_ a: Point3, _ b: Point3, _ c: Point3, material: Material) {
            let u = Point3(x: b.x - a.x, y: b.y - a.y, z: b.z - a.z)
            let v = Point3(x: c.x - a.x, y: c.y - a.y, z: c.z - a.z)
            let nx = u.y * v.z - u.z * v.y
            let ny = u.z * v.x - u.x * v.z
            let nz = u.x * v.y - u.y * v.x
            let magnitude = max(0.00001, (nx * nx + ny * ny + nz * nz).squareRoot())
            let n = Point3(x: nx / magnitude, y: ny / magnitude, z: nz / magnitude)
            buckets[material, default: Pending()].vertices.append(contentsOf: [a, b, c])
            buckets[material, default: Pending()].normals.append(contentsOf: [n, n, n])
        }

        func addQuad(_ a: Point3, _ b: Point3,
                     _ c: Point3, _ d: Point3, material: Material) {
            addTriangle(a, b, c, material: material)
            addTriangle(c, b, d, material: material)
        }

        func isSolid(_ x: Int, _ y: Int) -> Bool {
            guard let tile = world.tile(x: x, y: y) else { return false }
            if wasExcavated(x, y) || revealedTiles.contains(.init(x: x, y: y)) { return false }
            switch tile.excavation {
            case .wall, .hidden, .hiddenSlugHole, .unknown: return true
            case .exposed, .slugHole: return false
            }
        }

        func exposed(_ x: Int, _ z: Int) -> Bool {
            wasExcavated(x, z) || revealedTiles.contains(.init(x: x, y: z)) || world.tile(x: x, y: z)?.excavation.isDiscoveredCavern == true
        }

        func shouldRender(_ x: Int, _ z: Int) -> Bool {
            // Retail fog of war starts with exposed caverns, rather than
            // showing the entire map as a giant elevated grey plate. The
            // first ring of adjacent solid rock forms the cave wall.
            if exposed(x, z) { return true }
            guard isSolid(x, z) else { return false }
            return (-1...1).contains { dz in (-1...1).contains { dx in exposed(x + dx, z + dz) } }
        }

        func material(for tile: LevelWorld.Tile) -> Material {
            switch tile.terrain {
            case .immovable: return .immovable
            case .hard: return .hardRock
            case .medium: return .mediumRock
            case .dirt, .soil: return .dirt
            case .water, .lake: return .water
            case .lava: return .lava
            case .oreSeam: return .ore
            case .crystalSeam: return .crystal
            case .rechargeSeam: return .recharge
            default:
                return tile.excavation == .hidden || tile.excavation == .hiddenSlugHole ?
                    .hidden : .cavernFloor
            }
        }

        func vertex(_ x: Int, _ z: Int, extraHeight: Float = 0) -> Point3 {
            let height = Float(world.surfaceMap.value(x: x, y: z) ?? 0)
            return Point3(x: Float(x) - Float(world.width) / 2,
                          y: height * Self.previewHeightScale + extraHeight,
                          z: Float(z) - Float(world.height) / 2)
        }

        // Original destruction lowers the four shared MAP vertices. A wall
        // adjoining floor is therefore a triangulated slope, not a cube.
        func wallVertex(_ x: Int, _ z: Int) -> Point3 {
            let lowered = exposed(x, z) || exposed(x - 1, z) ||
                          exposed(x, z - 1) || exposed(x - 1, z - 1)
            return vertex(x, z, extraHeight: lowered ? 0 : Self.previewWallHeight)
        }

        for z in 0..<world.height {
            for x in 0..<world.width {
                guard shouldRender(x, z),
                      let tile = world.tile(x: x, y: z) else { continue }
                let wall = isSolid(x, z)
                let a = wall ? wallVertex(x, z) : vertex(x, z)
                let b = wall ? wallVertex(x + 1, z) : vertex(x + 1, z)
                let c = wall ? wallVertex(x, z + 1) : vertex(x, z + 1)
                let d = wall ? wallVertex(x + 1, z + 1) : vertex(x + 1, z + 1)
                // Each original 3D block picks its triangle diagonal from
                // the four HIGH map samples. Fixed triangulation distorted
                // steep seams, unlike the retail Map3D geometry.
                let h00 = world.surfaceMap.value(x: x, y: z) ?? 0
                let h10 = world.surfaceMap.value(x: x + 1, y: z) ?? 0
                let h01 = world.surfaceMap.value(x: x, y: z + 1) ?? 0
                let h11 = world.surfaceMap.value(x: x + 1, y: z + 1) ?? 0
                // Exposed rock is floor, not a rock/seam wall texture.
                let tileMaterial: Material = rubbleTiles.contains(.init(x: x, y: z)) ? .rubble : !wall && ![LevelWorld.Terrain.water, .lake, .lava].contains(tile.terrain) ? .cavernFloor : material(for: tile)
                if Self.usesUpperLeftDiagonal(topLeft: h00,
                                             topRight: h10,
                                             bottomLeft: h01,
                                             bottomRight: h11) {
                    // Diagonal a-d. Both triangles face +Y.
                    addTriangle(a, c, d, material: tileMaterial)
                    addTriangle(a, d, b, material: tileMaterial)
                } else {
                    // Default diagonal b-c. Both triangles face +Y.
                    addQuad(a, c, b, d, material: tileMaterial)
                }


            }
        }

        surfaces = Material.allCases.compactMap { material in
            guard let data = buckets[material], !data.vertices.isEmpty else { return nil }
            return Surface(material: material, vertices: data.vertices, normals: data.normals)
        }
        tileCount = count
        triangleCount = surfaces.reduce(0) { $0 + $1.triangleCount }
    }
}
