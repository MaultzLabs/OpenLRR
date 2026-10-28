import Foundation

/// A read-only, inspectable native scene assembled from original retail
/// Rock Raiders MAP resources. This is a verified world-loading milestone,
/// not a replacement for the 3D terrain renderer or gameplay simulation.
/// The first row/column boundary is carried in the MAP vertex dimensions;
/// playable tiles occupy (map.width - 1) × (map.height - 1).
struct LevelWorld {
    enum WorldError: Error, CustomStringConvertible {
        case missingRequiredMap(String)
        case invalidDimensions(String)

        var description: String {
            switch self {
            case .missingRequiredMap(let key):
                return "Original level has no required \(key) setting."
            case .invalidDimensions(let message):
                return "Incompatible original level maps: \(message)"
            }
        }
    }

    // Source: src/openlrr/game/GameCommon.h Lego_SurfaceType. Preserve
    // the numeric values of the *retail* terrain MAP rather than guessing
    // them from tile artwork. Lego_LoadTerrainMap also remaps code 5 to 4.
    enum Terrain: String {
        case tunnel = "Tunnel"
        case immovable = "Immovable rock"
        case hard = "Hard rock"
        case medium = "Medium rock"
        case dirt = "Dirt"
        case soil = "Soil (converted to dirt by retail)"
        case lava = "Lava"
        case water = "Water"
        case oreSeam = "Ore seam"
        case lake = "Lake"
        case crystalSeam = "Energy crystal seam"
        case rechargeSeam = "Recharge seam"
        case rubble = "Rubble"
        case reinforcement = "Reinforcement"
        case path = "Power path"
        case slugHole = "Slimy slug hole"
        case undiscovered = "Undiscovered"
        case cavern = "Cavern"
        case unknown = "Unrecognized terrain"

        init(code: UInt16) {
            switch code {
            case 0: self = .tunnel
            case 1: self = .immovable
            case 2: self = .hard
            case 3: self = .medium
            case 4: self = .dirt
            case 5: self = .soil
            case 6: self = .lava
            case 7: self = .water
            case 8: self = .oreSeam
            case 9: self = .lake
            case 10: self = .crystalSeam
            case 11: self = .rechargeSeam
            case 12: self = .rubble
            case 13: self = .reinforcement
            case 14: self = .path
            case 15: self = .slugHole
            case 16: self = .undiscovered
            case 17: self = .cavern
            default: self = .unknown
            }
        }

        var isLiquid: Bool { self == .lava || self == .water || self == .lake }
        var isMineableWall: Bool {
            switch self {
            case .medium, .dirt, .soil, .hard, .oreSeam, .crystalSeam:
                return true
            default: return false
            }
        }
    }

    enum Excavation: String {
        case wall = "Wall"
        case exposed = "Exposed cavern"
        case hidden = "Hidden cavern"
        case slugHole = "Slimy slug hole"
        case hiddenSlugHole = "Hidden slimy slug hole"
        case unknown = "Unknown"

        init(code: UInt16) {
            switch code {
            case 0: self = .wall
            case 1: self = .exposed
            case 2: self = .hidden
            case 3: self = .slugHole
            case 4: self = .hiddenSlugHole
            default: self = .unknown
            }
        }

        var isDiscoveredCavern: Bool {
            self == .exposed || self == .slugHole
        }

        var isCavern: Bool {
            self == .exposed || self == .hidden ||
            self == .slugHole || self == .hiddenSlugHole
        }
    }

    struct Tile {
        let x: Int
        let y: Int
        let terrainCode: UInt16
        let predugCode: UInt16
        let heightCode: UInt16

        var terrain: Terrain { Terrain(code: terrainCode) }
        var excavation: Excavation { Excavation(code: predugCode) }
    }

    let identifier: String
    let title: String
    /// Excludes the rightmost/bottommost extra MAP border vertex.
    let width: Int
    let height: Int
    let terrainMap: RockRaidersMap
    let predugMap: RockRaidersMap
    let surfaceMap: RockRaidersMap
    let blockPointersMap: RockRaidersMap?

    init(manifest: LevelRuntimeResources, resources: GameResources) throws {
        func required(_ key: String) throws -> RockRaidersMap {
            guard let path = manifest.mapPaths[key] else {
                throw WorldError.missingRequiredMap(key)
            }
            return try RockRaidersMap(data: resources.data(at: path,
                                                          maximumBytes: 32_000_000))
        }

        let terrain = try required("TerrainMap")
        let predug = try required("PredugMap")
        let surface = try required("SurfaceMap")
        guard terrain.width >= 2, terrain.height >= 2 else {
            throw WorldError.invalidDimensions("terrain map must contain at least two vertices per axis")
        }
        guard predug.width == terrain.width, predug.height == terrain.height,
              surface.width == terrain.width, surface.height == terrain.height else {
            throw WorldError.invalidDimensions("terrain, predug and surface dimensions differ")
        }
        self.identifier = manifest.identifier
        self.title = manifest.title
        self.width = terrain.width - 1
        self.height = terrain.height - 1
        self.terrainMap = terrain
        self.predugMap = predug
        self.surfaceMap = surface
        if manifest.mapPaths["BlockPointersMap"] != nil {
            let pointers = try required("BlockPointersMap")
            guard pointers.width == terrain.width, pointers.height == terrain.height else {
                throw WorldError.invalidDimensions("block-pointer and terrain dimensions differ")
            }
            self.blockPointersMap = pointers
        } else { self.blockPointersMap = nil }
    }

    /// Zero is unmarked; repeated IDs designate every matching playable tile.
    func tutorialBlocks(_ id: Int32) -> [(x: Int, y: Int)] {
        guard id > 0, id <= 255, let map = blockPointersMap else { return [] }
        var result: [(x: Int, y: Int)] = []
        for y in 0..<height {
            for x in 0..<width where map.value(x: x, y: y) == UInt16(id) {
                result.append((x, y))
            }
        }
        return result
    }

    func tile(x: Int, y: Int) -> Tile? {
        guard (0..<width).contains(x), (0..<height).contains(y),
              let terrain = terrainMap.value(x: x, y: y),
              let predug = predugMap.value(x: x, y: y),
              let height = surfaceMap.value(x: x, y: y) else { return nil }
        return Tile(x: x, y: y, terrainCode: terrain,
                    predugCode: predug, heightCode: height)
    }

    /// Evaluate the same planar HIGH-map triangles as NativeTerrainMesh.
    /// Bilinear interpolation does not lie on either rendered triangle when
    /// the four retail height samples are non-coplanar; that made cameras
    /// and original OL placement markers visibly float or sink into slopes.
    /// Coordinates are in MAP tile units, including the final border vertex.
    /// This does not yet reproduce the retail engine's roughness perturbation.
    func elevation(atX x: Double, y: Double) -> Float? {
        guard x.isFinite, y.isFinite,
              x >= 0, y >= 0, x <= Double(width), y <= Double(height) else {
            return nil
        }
        // At the last border vertex use the adjacent playable tile, so
        // both edge vertices and interior points share the mesh's plane.
        let x0 = min(width - 1, Int(floor(x)))
        let y0 = min(height - 1, Int(floor(y)))
        guard let a = surfaceMap.value(x: x0, y: y0),
              let b = surfaceMap.value(x: x0 + 1, y: y0),
              let c = surfaceMap.value(x: x0, y: y0 + 1),
              let d = surfaceMap.value(x: x0 + 1, y: y0 + 1) else { return nil }
        let u = Float(x - Double(x0))
        let v = Float(y - Double(y0))
        if abs(Int(a) - Int(d)) < abs(Int(b) - Int(c)) {
            // a--d diagonal; split by u == v.
            if u <= v {
                return Float(a) * (1 - v) + Float(c) * (v - u) + Float(d) * u
            }
            return Float(a) * (1 - u) + Float(d) * v + Float(b) * (u - v)
        }
        // b--c diagonal; split by u + v == 1.
        if u + v <= 1 {
            return Float(a) * (1 - u - v) + Float(b) * u + Float(c) * v
        }
        return Float(b) * (1 - v) + Float(c) * (1 - u) +
               Float(d) * (u + v - 1)
    }

    var initialCameraTile: (x: Int, y: Int) {
        // When a level has no explicit camera location, center on the first
        // exposed cavern, not on inaccessible solid rock in a distant corner.
        // The original StartFP/OL camera is not yet supported.
        for y in 0..<height {
            for x in 0..<width {
                if let tile = tile(x: x, y: y),
                   tile.excavation.isDiscoveredCavern {
                    return (x, y)
                }
            }
        }
        return (width / 2, height / 2)
    }
}
