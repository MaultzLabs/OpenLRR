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

        /// Only accept the retail families, not arbitrary paths that happen
        /// to contain "rock" or "ice" in a directory or filename.
        init?(setting: String) {
            switch setting.lowercased() {
            case "rock": self = .rock
            case "ice": self = .ice
            case "lava": self = .lava
            default: return nil
            }
        }
    }

    let family: Family
    let rootPrefix: String

    /// Lego.cfg TextureSet is a texture *prefix* followed by two colon
    /// fields (for example World\\WorldTextures\\RockSplit\\Rock:0:0).
    /// The game appends two hex digits to the prefix for individual BMPs.
    /// Parse the setting rather than guessing a biome from a substring.
    /// The trailing numeric fields are retained by the configuration layer;
    /// they are not part of the BMP filename.
    private static func configuredSet(_ raw: String) -> (Family, String)? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count == 1 || fields.count == 3 else { return nil }
        if fields.count == 3 {
            guard Int(fields[1]) != nil, Int(fields[2]) != nil else { return nil }
        }
        let prefix = String(fields[0]).replacingOccurrences(of: "\\", with: "/")
        guard !prefix.isEmpty, prefix.count <= 256,
              !prefix.hasPrefix("/"),
              !prefix.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !prefix.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { return nil }

        if let family = Family(setting: prefix) {
            return (family, family.pathPrefix)
        }
        for family in Family.allCases where
            prefix.caseInsensitiveCompare(family.pathPrefix) == .orderedSame {
            return (family, prefix)
        }
        return nil
    }

    init?(textureSetSetting: String?, resources: GameResources) {
        if let setting = textureSetSetting, !setting.isEmpty {
            guard let (chosenFamily, prefix) = Self.configuredSet(setting),
                  resources.exists(Self.imagePath(prefix: prefix, textureID: 0)) else {
                // A specified but missing/invalid set must not silently
                // render the wrong biome with a different family's BMPs.
                return nil
            }
            family = chosenFamily
            rootPrefix = prefix
            return
        }
        // Some older level configurations omit TextureSet. Only in that
        // case discover an installed retail family as a preview fallback.
        for candidate in Family.allCases {
            if resources.exists(Self.imagePath(prefix: candidate.pathPrefix,
                                               textureID: 0)) {
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
