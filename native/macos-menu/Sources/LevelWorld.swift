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

    enum Terrain: String {
        case unknown = "Unspecified"
        case solid = "Solid rock"
        case hard = "Hard rock"
        case loose = "Loose rock"
        case dirt = "Dirt"
        case soil = "Soil"
        case lava = "Lava"
        case waterSheet = "Water sheet"
        case oreSeam = "Ore seam"
        case water = "Water"
        case crystalSeam = "Energy crystal seam"
        case rechargeSeam = "Recharge seam"

        init(code: UInt16) {
            switch code {
            case 1: self = .solid
            case 2: self = .hard
            case 3: self = .loose
            case 4: self = .dirt
            case 5: self = .soil
            case 6: self = .lava
            case 7: self = .waterSheet
            case 8: self = .oreSeam
            case 9: self = .water
            case 10: self = .crystalSeam
            case 11: self = .rechargeSeam
            default: self = .unknown
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
    }

    func tile(x: Int, y: Int) -> Tile? {
        guard (0..<width).contains(x), (0..<height).contains(y),
              let terrain = terrainMap.value(x: x, y: y),
              let predug = predugMap.value(x: x, y: y),
              let height = surfaceMap.value(x: x, y: y) else { return nil }
        return Tile(x: x, y: y, terrainCode: terrain,
                    predugCode: predug, heightCode: height)
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
