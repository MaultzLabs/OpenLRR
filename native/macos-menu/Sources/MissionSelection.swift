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
        self.tutorials = Self.build(config: config, levels: catalog.tutorials, unlockAll: true)
    }

    private static func build(config: LegoConfig, levels: [LevelCatalog.Level], unlockAll: Bool = false) -> [Node] {
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
            // Front_Levels_UpdateAvailable passes keepLocked=false for tutorials,
            // so every tutorial is available. New missions unlock from root
            // or the explicit FrontEndOpen flag until a save is loaded.
            let initiallyAvailable = unlockAll || root || ["true", "yes", "on", "1"].contains(open ?? "")

            // Front_LevelInfo_Callback_AddItem uses Menu::DefaultLevelBMPS
            // if a particular level omits MenuBMP.
            let fallbackImages = (config.valueUnderGame(["Menu", "DefaultLevelBMPS"]) ?? "")
                .split(separator: ",", omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let paths = level.menuBitmapPaths.count == 3 ? level.menuBitmapPaths :
                        (fallbackImages.count == 3 ? fallbackImages : [])

            result.append(Node(identifier: level.identifier, title: level.fullName,
                               imagePaths: paths,
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
/// Read-only native session overlay for genuine NERPs level completion.
/// Mirrors the original Front_Levels_UpdateAvailable link rule: completing a
/// level unlocks that level and its immediate LevelLinks children. FrontEndOpen
/// is not completion. The overlay is discarded when archives or save slots
/// change; it never writes or mutates the original PC .sav files.
struct MissionSessionProgress {
    private(set) var completedIdentifiers: Set<String> = []

    @discardableResult
    mutating func recordCompletion(_ identifier: String,
                                   missions: [MissionSelection.Node]) -> Bool {
        guard let node = missions.first(where: {
            $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame
        }) else { return false }
        return completedIdentifiers.insert(node.identifier.lowercased()).inserted
    }

    mutating func reset() {
        completedIdentifiers.removeAll()
    }

    func isAvailable(_ node: MissionSelection.Node,
                     among nodes: [MissionSelection.Node],
                     savedCompleted: Set<String> = []) -> Bool {
        if node.initiallyAvailable { return true }
        let completed = completedIdentifiers.union(savedCompleted.map { $0.lowercased() })
        let key = node.identifier.lowercased()
        if completed.contains(key) { return true }
        return nodes.contains { parent in
            completed.contains(parent.identifier.lowercased()) &&
            parent.nextIdentifiers.contains { $0.lowercased() == key }
        }
    }
}


/// An explicit, native-only export of session unlocks. This is NOT a PC SaveData
/// or SaveReward serializer. The user chooses the JSON file in a Save panel;
/// no game file, original .sav, or Application Support data is ever changed
/// automatically. A user-supplied import is not evidence of a retail playthrough.
struct NativeCampaignProgressArchive: Codable {
    enum ArchiveError: Error, LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let reason): return "Invalid native campaign progress: \(reason)"
            }
        }
    }

    static let version = 1
    static let maximumBytes = 64 * 1024

    let formatVersion: Int
    /// Exact order and identifiers of the currently loaded original mission
    /// selection. This prevents applying a different game's unlock graph.
    let missionIdentifiers: [String]
    /// Only campaign nodes can be stored; tutorial names are rejected.
    let completedIdentifiers: [String]
    /// One-based original save-slot number, or nil if no PC save was selected.
    /// This prevents silently transferring a sidecar across original slots.
    let originalSaveSlot: Int?

    static func export(_ progress: MissionSessionProgress,
                       missions: [MissionSelection.Node],
                       originalSaveSlot: Int?) throws -> Data {
        guard (1...150).contains(missions.count),
              originalSaveSlot == nil || (1...5).contains(originalSaveSlot!) else {
            throw ArchiveError.invalid("invalid mission catalogue or original save slot")
        }
        let archive = Self(
            formatVersion: Self.version,
            missionIdentifiers: missions.map(\.identifier),
            completedIdentifiers: progress.completedIdentifiers.sorted(),
            originalSaveSlot: originalSaveSlot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        guard data.count <= maximumBytes else {
            throw ArchiveError.invalid("archive is too large")
        }
        return data
    }

    static func restore(_ data: Data,
                        missions: [MissionSelection.Node],
                        originalSaveSlot: Int?) throws -> MissionSessionProgress {
        guard !data.isEmpty, data.count <= maximumBytes else {
            throw ArchiveError.invalid("file is empty or exceeds 64 KiB")
        }
        let archive: Self
        do {
            archive = try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw ArchiveError.invalid("unrecognized JSON format")
        }
        guard archive.formatVersion == version else {
            throw ArchiveError.invalid("unsupported native progress version")
        }
        guard archive.originalSaveSlot == originalSaveSlot else {
            throw ArchiveError.invalid("select the same original save slot first")
        }
        let expected = missions.map { $0.identifier.lowercased() }
        guard (1...150).contains(missions.count),
              archive.missionIdentifiers.map({ $0.lowercased() }) == expected else {
            throw ArchiveError.invalid("original mission catalogue differs")
        }
        guard archive.completedIdentifiers.count <= missions.count else {
            throw ArchiveError.invalid("too many completed missions")
        }
        var progress = MissionSessionProgress()
        for identifier in archive.completedIdentifiers {
            // Also rejects duplicates differing only in case and identifiers
            // that are not original mission-map nodes, including tutorials.
            guard progress.recordCompletion(identifier, missions: missions) else {
                throw ArchiveError.invalid("unknown or duplicate completed mission")
            }
        }
        return progress
    }
}
