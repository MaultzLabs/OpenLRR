import Foundation

/// Finds the actual world BMP textures INSIDE the user's original WADs.
/// World/WorldTextures/{Rock,Ice,Lava}Split/{ROCK,ICE,LAVA}XX.BMP,
/// where XX is the hexadecimal SurfaceTexture ID (GameCommon.h).
///
/// All bytes stay in the private original archive; no repacking, substitute
/// downloads, texture-generation, or copyrighted files in this repository.
/// A level's Lego.cfg TextureSet selects the intended Rock/Ice/Lava family.
struct OriginalTerrainTextureCatalog {
    enum Family: String, CaseIterable {
        case rock = "Rock"
        case ice = "Ice"
        case lava = "Lava"

        var pathPrefix: String {
            "World/WorldTextures/\(rawValue)Split/\(rawValue)"
        }

        init?(setting: String) {
            let normalized = setting.replacingOccurrences(of: "\\", with: "/")
                .lowercased()
            if normalized.contains("ice") { self = .ice }
            else if normalized.contains("lava") { self = .lava }
            else if normalized.contains("rock") { self = .rock }
            else { return nil }
        }
    }

    let family: Family
    let rootPrefix: String

    init?(textureSetSetting: String?, resources: GameResources) {
        let requested: [Family]
        if let setting = textureSetSetting, let matched = Family(setting: setting) {
            requested = [matched]
        } else {
            requested = [.rock, .ice, .lava]
        }

        for candidate in requested {
            let path = Self.imagePath(prefix: candidate.pathPrefix, textureID: 0)
            if resources.exists(path) {
                family = candidate
                rootPrefix = candidate.pathPrefix
                return
            }
        }
        return nil
    }

    static func imagePath(prefix: String, textureID: UInt8) -> String {
        String(format: "%@%02X.BMP", prefix, textureID)
    }

    func path(for textureID: UInt8, resources: GameResources) -> String? {
        let path = Self.imagePath(prefix: rootPrefix, textureID: textureID)
        return resources.exists(path) ? path : nil
    }

    func bytes(for textureID: UInt8, resources: GameResources) -> Data? {
        guard let path = path(for: textureID, resources: resources) else { return nil }
        return try? resources.data(at: path, maximumBytes: 4_000_000)
    }

    /// Source: SurfaceTexture enum in src/openlrr/game/GameCommon.h.
    /// This is a preliminary representative mapping, not the complete
    /// retail Map3D per-block transition/direction texture algorithm.
    static func representativeID(for terrain: LevelWorld.Terrain) -> UInt8 {
        switch terrain {
        case .immovable: return 0x05
        case .hard: return 0x04
        case .medium: return 0x03
        case .dirt, .soil: return 0x02
        case .oreSeam: return 0x40
        case .crystalSeam: return 0x20
        case .rechargeSeam: return 0x67
        case .water, .lake: return 0x45
        case .lava: return 0x46
        case .slugHole: return 0x30
        case .path: return 0x60
        default: return 0x00
        }
    }
}
