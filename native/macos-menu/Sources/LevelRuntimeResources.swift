import Foundation

/// Resolves each real level's terrain and world files from Lego.cfg.
/// See Lego_LoadLevel and the retail Level01 config: SurfaceMap (height),
/// PredugMap (exposed and hidden caverns), TerrainMap (rock type), etc.
/// No 3D world is synthesized, no gameplay actions are simulated.
struct LevelRuntimeResources {
    enum RuntimeError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self {
            case .invalid(let message): return "Invalid original level: \(message)"
            }
        }
    }

    static let mapKeys = [
        "SurfaceMap", "PredugMap", "TerrainMap", "CryOreMap", "ErodeMap",
        "EmergeMap", "PathMap", "BlockPointersMap", "FallinMap", "AIMap"
    ]

    let identifier: String
    let title: String
    let mapPaths: [String: String]
    let textureSetSetting: String?
    let objectListPath: String?
    let scriptPath: String?
    let scriptMessagePath: String?
    let objectiveTextPath: String?
    let nextLevel: String?

    init(config: LegoConfig, identifier: String) throws {
        let path = identifier.components(separatedBy: "::")
        guard path.count >= 2, path.allSatisfy({ !$0.isEmpty }),
              path.first?.lowercased() == "levels" else {
            throw RuntimeError.invalid("expected a Levels:: identifier")
        }
        self.identifier = identifier
        self.title = (config.valueUnderGame(path + ["FullName"]) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")

        func safePath(_ key: String) throws -> String? {
            guard let value = config.valueUnderGame(path + [key]), !value.isEmpty else {
                return nil
            }
            // The original game accepts relative Windows data paths only.
            // Reject parent traversal, absolute roots, and drive references
            // before they are ever passed to the filesystem or WAD reader.
            let segments = value.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: false)
            guard !segments.isEmpty, segments.allSatisfy({
                !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":")
            }) else {
                throw RuntimeError.invalid("unsafe \(key) path in \(identifier)")
            }
            return value
        }

        var paths: [String: String] = [:]
        for key in Self.mapKeys {
            if let filename = try safePath(key) { paths[key] = filename }
        }
        self.mapPaths = paths
        // TextureSet is *not* a pathname. Retail Lego.cfg can use a
        // colon-separated texture atlas descriptor (the value may contain
        // colons or commas), so passing it through safePath incorrectly
        // rejects working missions such as Levels::Level01.
        let textureDescriptor = config.valueUnderGame(path + ["TextureSet"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let descriptor = textureDescriptor, descriptor.contains("::") {
            let reference = descriptor.components(separatedBy: "::")
            // Retail TextureSet is a reference to Textures::{Rock,Ice,Lava}.
            // Resolve its TextureBaseName instead of treating :: as atlas fields.
            guard reference.count == 2, reference[0].lowercased() == "textures",
                  !reference[1].isEmpty,
                  let prefix = config.valueUnderGame(reference + ["TextureBaseName"]),
                  !prefix.isEmpty, prefix.utf8.count <= 2048 else {
                throw RuntimeError.invalid("unresolved TextureSet reference: \(descriptor)")
            }
            self.textureSetSetting = prefix
        } else {
            self.textureSetSetting = (textureDescriptor?.utf8.count ?? 0) <= 2048
                ? textureDescriptor : nil
        }
        self.objectListPath = try safePath("OListFile")
        self.scriptPath = try safePath("NERPFile")
        self.scriptMessagePath = try safePath("NERPMessageFile")
        self.objectiveTextPath = try safePath("ObjectiveText")
        self.nextLevel = config.valueUnderGame(path + ["NextLevel"])
    }

    /// Decode original 16-bit map cells from the user's WADs, without
    /// making temporary extracted copies or changing the files.
    func loadMaps(resources: GameResources) throws -> [String: RockRaidersMap] {
        var maps: [String: RockRaidersMap] = [:]
        for key in Self.mapKeys {
            guard let path = mapPaths[key] else { continue }
            let bytes = try resources.data(at: path, maximumBytes: 32_000_000)
            maps[key] = try RockRaidersMap(data: bytes)
        }
        return maps
    }
}
