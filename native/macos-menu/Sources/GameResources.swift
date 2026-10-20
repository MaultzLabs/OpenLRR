import Foundation

/// The Windows game searches a family of LegoRR*.wad archives. For the original
/// retail install, index 1 (language and Lego.cfg) overrides index 0 (main art).
/// The native prototype opens ONLY the explicit user-selected archive pair.
struct GameResources {
    enum ResourceError: Error, CustomStringConvertible {
        case missingArchive(String)
        case missingAsset(String)
        case invalidSelection(String)

        var description: String {
            switch self {
            case .missingArchive(let value): return "Required archive missing: \(value)"
            case .missingAsset(let value): return "Asset not found: \(value)"
            case .invalidSelection(let value): return "Invalid game archive selection: \(value)"
            }
        }
    }

    struct Archive {
        let index: Int
        let wad: WadArchive
    }

    private let archives: [Archive]  // Highest index first; preserve original priority.

    init(archives: [(Int, Data)]) throws {
        guard !archives.isEmpty, archives.count <= 10 else {
            throw ResourceError.invalidSelection("expected 1 to 10 archives")
        }
        var loaded: [Archive] = []
        var indices = Set<Int>()
        for (index, data) in archives {
            guard (0...9).contains(index), indices.insert(index).inserted else {
                throw ResourceError.invalidSelection("archive indexes must be unique and within 0...9")
            }
            loaded.append(Archive(index: index, wad: try WadArchive(data: data)))
        }
        self.archives = loaded.sorted { $0.index > $1.index }
    }

    /// Only the selected WAD plus a sibling file named LegoRR0/1.wad may be read.
    /// Never recursively searches a user's filesystem or writes to the game folder.
    init(selectedWadURL: URL) throws {
        let filename = selectedWadURL.lastPathComponent.lowercased()
        guard filename == "legorr0.wad" || filename == "legorr1.wad" else {
            throw ResourceError.invalidSelection("choose LegoRR0.wad or LegoRR1.wad")
        }
        let directory = selectedWadURL.deletingLastPathComponent()
        let siblings = try FileManager.default.contentsOfDirectory(at: directory,
                         includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        var inputs: [(Int, Data)] = []
        for index in 0...1 {
            let expected = "legorr\(index).wad"
            if let url = siblings.first(where: { $0.lastPathComponent.lowercased() == expected }) {
                let size = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard size.isRegularFile == true, let length = size.fileSize,
                      length <= 1_000_000_000 else {
                    throw ResourceError.invalidSelection("invalid WAD file type or size")
                }
                inputs.append((index, try Data(contentsOf: url, options: [.mappedIfSafe])))
            }
        }
        guard inputs.contains(where: { $0.0 == 0 }) else {
            throw ResourceError.missingArchive("LegoRR0.wad")
        }
        try self.init(archives: inputs)
    }

    var mountedIndices: [Int] { archives.map { $0.index } }

    func exists(_ path: String) -> Bool {
        archives.contains { $0.wad.contains(path) }
    }

    func data(at path: String, maximumBytes: Int = 50_000_000) throws -> Data {
        for archive in archives where archive.wad.contains(path) {
            // Fail closed if the higher-priority entry is corrupt or compressed.
            // Never silently use a lower-priority version instead.
            return try archive.wad.asset(path, maximumBytes: maximumBytes)
        }
        throw ResourceError.missingAsset(path)
    }

    func configData() throws -> Data { try data(at: "Lego.cfg", maximumBytes: 10_000_000) }

    func list(prefix: String = "") -> [String] {
        let normalized = WadArchive.normalized(prefix)
        var seen = Set<String>()
        return archives.flatMap { archive in
            archive.wad.entries.compactMap { entry -> String? in
                let key = WadArchive.normalized(entry.path)
                guard key.hasPrefix(normalized), seen.insert(key).inserted else { return nil }
                return entry.path
            }
        }
    }
}
