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

    init(world: LevelWorld, maxTiles: Int = 150_000) throws {
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
            switch tile.excavation {
            case .wall, .hidden, .hiddenSlugHole, .unknown: return true
            case .exposed, .slugHole: return false
            }
        }

        func exposed(_ x: Int, _ z: Int) -> Bool {
            world.tile(x: x, y: z)?.excavation.isDiscoveredCavern == true
        }

        func shouldRender(_ x: Int, _ z: Int) -> Bool {
            // Retail fog of war starts with exposed caverns, rather than
            // showing the entire map as a giant elevated grey plate. The
            // first ring of adjacent solid rock forms the cave wall.
            if exposed(x, z) { return true }
            guard isSolid(x, z) else { return false }
            return exposed(x - 1, z) || exposed(x + 1, z) ||
                   exposed(x, z - 1) || exposed(x, z + 1)
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

        for z in 0..<world.height {
            for x in 0..<world.width {
                guard shouldRender(x, z),
                      let tile = world.tile(x: x, y: z) else { continue }
                let wall = isSolid(x, z)
                let lift = wall ? Self.previewWallHeight : 0
                let a = vertex(x, z, extraHeight: lift)
                let b = vertex(x + 1, z, extraHeight: lift)
                let c = vertex(x, z + 1, extraHeight: lift)
                let d = vertex(x + 1, z + 1, extraHeight: lift)
                // CCW when viewed from above, with positive world Y normal.
                addQuad(a, c, b, d, material: material(for: tile))

                guard wall else { continue }

                // Wall faces only along uncovered edges. Internal boundaries
                // are not drawn, keeping real-world levels affordable.
                if z == 0 || !isSolid(x, z - 1) {
                    addQuad(a, vertex(x, z), b, vertex(x + 1, z),
                            material: .wallFace)
                }
                if z == world.height - 1 || !isSolid(x, z + 1) {
                    addQuad(d, vertex(x + 1, z + 1), c, vertex(x, z + 1),
                            material: .wallFace)
                }
                if x == 0 || !isSolid(x - 1, z) {
                    addQuad(c, vertex(x, z + 1), a, vertex(x, z),
                            material: .wallFace)
                }
                if x == world.width - 1 || !isSolid(x + 1, z) {
                    addQuad(b, vertex(x + 1, z), d, vertex(x + 1, z + 1),
                            material: .wallFace)
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
