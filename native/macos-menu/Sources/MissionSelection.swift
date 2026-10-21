import Foundation

/// Reproduces the front-end's actual level-link traversal without starting a
/// mission. OpenLRR: Front_LoadLevelSet builds NextLevel order, then
/// Front_LevelSet_LoadLevelLinks and Front_LevelLink_RunThroughLinks determine
/// the order of select icons (src/openlrr/game/front/FrontEnd.cpp).
///
/// This is not a gameplay engine and does not unlock missions or write saves.
struct MissionSelection {
    struct Node {
        let identifier: String
        let title: String
        /// In the original order: highlighted, normal, locked.
        let imagePaths: [String]
        let x: Int
        let y: Int
        let initiallyAvailable: Bool
        let nextIdentifiers: [String]
    }

    let missions: [Node]
    let tutorials: [Node]

    init(config: LegoConfig, catalog: LevelCatalog) {
        self.missions = Self.build(config: config, levels: catalog.missions)
        self.tutorials = Self.build(config: config, levels: catalog.tutorials)
    }

    private static func build(config: LegoConfig, levels: [LevelCatalog.Level]) -> [Node] {
        guard let first = levels.first else { return [] }
        let byID = Dictionary(uniqueKeysWithValues: levels.map { ($0.identifier.lowercased(), $0) })
        var visited = Set<String>()
        var result: [Node] = []
        result.reserveCapacity(levels.count)

        func visit(_ identifier: String, root: Bool) {
            let key = identifier.lowercased()
            guard !visited.contains(key), let level = byID[key] else { return }
            visited.insert(key)

            let segments = level.identifier.components(separatedBy: "::")
            let rawLinks = config.valueUnderGame(segments + ["LevelLinks"]) ?? ""
            let links = rawLinks.split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let open = config.valueUnderGame(segments + ["FrontEndOpen"])?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let initiallyAvailable = root || ["true", "yes", "on", "1"].contains(open ?? "")

            result.append(Node(identifier: level.identifier, title: level.fullName,
                               imagePaths: level.menuBitmapPaths,
                               x: level.positionX ?? 0, y: level.positionY ?? 0,
                               initiallyAvailable: initiallyAvailable,
                               nextIdentifiers: links))

            // A loop or malformed reference is ignored, as in Front_LevelSet's
            // visited/lookup behavior. No invented mission is created.
            for link in links where result.count < 150 {
                visit(link, root: false)
            }
        }

        visit(first.identifier, root: true)
        return result
    }
}
