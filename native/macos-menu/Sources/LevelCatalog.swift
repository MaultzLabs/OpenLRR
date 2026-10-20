import Foundation

/// Reads the game's actual mission/tutorial order from Lego.cfg instead of
/// inventing missions. Front_LoadLevelSet walks Main/StartLevel and NextLevel.
struct LevelCatalog {
    enum CatalogError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let message): return "Invalid level sequence: \(message)" }
        }
    }

    struct Level {
        let identifier: String
        let fullName: String
        let menuBitmapPaths: [String]
        let positionX: Int?
        let positionY: Int?
    }

    let missions: [Level]
    let tutorials: [Level]

    init(config: LegoConfig) throws {
        self.missions = try Self.load(config: config, firstSetting: "StartLevel")
        self.tutorials = try Self.load(config: config, firstSetting: "TutorialStartLevel")
    }

    private static func load(config: LegoConfig, firstSetting: String) throws -> [Level] {
        guard var identifier = config.valueUnderGame(["Main", firstSetting]),
              !identifier.isEmpty else { return [] }
        var visited = Set<String>()
        var result: [Level] = []
        for _ in 0..<150 {
            // The retail CFG uses paths like Levels::Level01; preserve this
            // hierarchy and the original localized FullName values.
            let parts = identifier.components(separatedBy: "::")
            guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else {
                throw CatalogError.invalid("bad level identifier \(identifier)")
            }
            guard visited.insert(identifier.lowercased()).inserted else {
                throw CatalogError.invalid("NextLevel cycle at \(identifier)")
            }
            let name = config.valueUnderGame(parts + ["FullName"])?
                .replacingOccurrences(of: "_", with: " ") ?? identifier
            let images = (config.valueUnderGame(parts + ["MenuBMP"]) ?? "")
                .split(separator: ",", omittingEmptySubsequences: true).map(String.init)
            let x = config.valueUnderGame(parts + ["FrontEndX"]).flatMap(Int.init)
            let y = config.valueUnderGame(parts + ["FrontEndY"]).flatMap(Int.init)
            result.append(Level(identifier: identifier, fullName: name,
                                menuBitmapPaths: images, positionX: x, positionY: y))
            guard let next = config.valueUnderGame(parts + ["NextLevel"]),
                  !next.isEmpty else { return result }
            identifier = next
        }
        throw CatalogError.invalid("mission chain exceeds 150 levels")
    }
}
