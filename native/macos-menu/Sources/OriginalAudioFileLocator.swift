import Foundation

/// Resolves user-owned original audio without copying or changing it.
///
/// Rock Raiders stores sound effects in both WAD archives and loose files
/// beneath Data/Sounds (including Data/Sounds/Streamed). A user may have
/// selected a WAD located in the install folder OR directly inside Data.
/// Paths in Lego.cfg use Windows separators and casing, whereas the host file
/// system may be case-sensitive.
struct OriginalAudioFileLocator {
    static func locate(_ configuredPath: String, beside selectedWadURL: URL,
                       additionalRoot: URL? = nil,
                       fileManager: FileManager = .default,
                       homeDirectory: URL? = nil) -> URL? {
        locateAll(configuredPath, beside: selectedWadURL,
                  additionalRoot: additionalRoot, fileManager: fileManager,
                  homeDirectory: homeDirectory).first
    }

    /// Do not stop at the first WAV. Some LRR installations contain corrupted
    /// CAB-extracted menu WAVs; a valid CD/RRU WAV may exist in another
    /// already-installed location. Playback can try each candidate in order.
    static func locateAll(_ configuredPath: String, beside selectedWadURL: URL,
                          additionalRoot: URL? = nil,
                          fileManager: FileManager = .default,
                          homeDirectory: URL? = nil) -> [URL] {
        let normalized = configuredPath.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 32,
              parts.last?.lowercased().hasSuffix(".wav") == true,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                                 !$0.contains(":") && !$0.contains("\0") }) else {
            return []
        }

        let wadDirectory = selectedWadURL.deletingLastPathComponent()
        let home = homeDirectory ?? fileManager.homeDirectoryForCurrentUser
        let nearby = [wadDirectory, wadDirectory.appendingPathComponent("Data", isDirectory: true),
                      wadDirectory.deletingLastPathComponent().appendingPathComponent("Data", isDirectory: true)]
        // A typical Rock Raiders install has its original sound outside the WADs.
        // Search only known game-install and RRU download locations, not the
        // user's entire home folder. Do not require a second file picker.
        let discoveryRoots = automaticAudioRoots(home: home, fileManager: fileManager)
        let roots = nearby + discoveryRoots + (additionalRoot.map { [$0] } ?? [])

        var matches: [URL] = []
        var seenPaths = Set<String>()
        for root in roots {
            var candidates = [parts]
            // A known game install directory normally keeps loose sounds at
            // Data/Sounds/Streamed, not in its root.
            if root.lastPathComponent.lowercased() != "data" &&
               parts.first?.lowercased() == "sounds" {
                candidates.append(["Data"] + parts)
            }
            // A user may select the game installation itself, Data/, Sounds/,
            // Streamed/, or a ZIP extraction folder. Probe only beneath that
            // explicitly selected directory; never walk arbitrary parents.
            if let additionalRoot, root.standardizedFileURL == additionalRoot.standardizedFileURL {
                let head = parts.first?.lowercased()
                if head == "sounds" {
                    candidates.append(["Data"] + parts)
                }
                if head == "data" {
                    candidates.append(Array(parts.dropFirst()))
                }
                if head != "sounds" && head != "data" {
                    candidates.append(["Data", "Sounds", "Streamed"] + parts)
                    candidates.append(["Sounds", "Streamed"] + parts)
                }
            }
            // RRU's standalone Atmosdel_and_Stats.zip can be extracted to a
            // directory containing WAVs directly. Only allow basename lookup
            // inside the folder that the user explicitly selected.
            if let filename = parts.last,
               (root.lastPathComponent.lowercased().contains("atmosdel") ||
                (additionalRoot != nil && root.standardizedFileURL == additionalRoot?.standardizedFileURL)) {
                candidates.append([filename])
            }
            let rootName = root.lastPathComponent.lowercased()
            if rootName == "sounds", parts.first?.lowercased() == "sounds" {
                candidates.append(Array(parts.dropFirst()))
            }
            if rootName == "streamed", parts.count >= 3,
               parts[0].lowercased() == "sounds", parts[1].lowercased() == "streamed" {
                candidates.append(Array(parts.dropFirst(2)))
            }
            if rootName == "data", parts.first?.lowercased() == "data" {
                candidates.append(Array(parts.dropFirst()))
            }

            for candidate in candidates {
                guard let url = resolveCaseInsensitive(root: root, components: candidate,
                                                       fileManager: fileManager) else { continue }
                guard let info = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      info.isRegularFile == true, let size = info.fileSize,
                      (44...100_000_000).contains(size) else { continue }
                if seenPaths.insert(url.standardizedFileURL.path).inserted {
                    matches.append(url)
                }
            }
        }
        return matches
    }

    /// Bounded discovery of standard user-owned installations. The original
    /// Windows sound assets often exist in a Wineskin/Wine wrapper, even when
    /// the user opened a copied WAD from Downloads. We inspect directory names
    /// only; game files are opened by locate() when their exact path matches.
    static func automaticAudioRoots(home: URL, fileManager: FileManager = .default) -> [URL] {
        var roots: [URL] = []
        var seen = Set<String>()

        func include(_ candidate: URL) {
            let url = candidate.standardizedFileURL
            let path = url.path
            var isDirectory: ObjCBool = false
            guard !seen.contains(path),
                  fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { return }
            seen.insert(path)
            roots.append(url)
        }

        let downloads = home.appendingPathComponent("Downloads", isDirectory: true)
        include(downloads)
        if let names = try? fileManager.contentsOfDirectory(atPath: downloads.path) {
            // Extracted copies of RRU's menu-audio download.
            for name in names.prefix(256) where name.lowercased().contains("atmosdel") {
                include(downloads.appendingPathComponent(name, isDirectory: true))
            }
        }

        let wrapperContainers = [home.appendingPathComponent("Applications/Sikarugir", isDirectory: true),
                                 home.appendingPathComponent("Applications", isDirectory: true)]
        // Official Wine's default drive_C path, for installs not inside an app.
        let wineDrive = home.appendingPathComponent(".wine/drive_c", isDirectory: true)
        for programFiles in ["Program Files", "Program Files (x86)"] {
            let programs = wineDrive.appendingPathComponent(programFiles, isDirectory: true)
            addGameDirectories(in: programs, to: &roots, seen: &seen, fileManager: fileManager)
        }

        // Limit scan depth to .app -> Contents/SharedSupport -> prefix/drive_c
        // -> Program Files -> Rock Raiders *. Never traverse arbitrary trees.
        for wrapperContainer in wrapperContainers {
            guard let names = try? fileManager.contentsOfDirectory(atPath: wrapperContainer.path) else { continue }
            for name in names.prefix(96) where name.lowercased().hasSuffix(".app") {
                let bundle = wrapperContainer.appendingPathComponent(name, isDirectory: true)
                let drive = bundle.appendingPathComponent("Contents/SharedSupport/prefix/drive_c", isDirectory: true)
                for programFiles in ["Program Files", "Program Files (x86)"] {
                    addGameDirectories(in: drive.appendingPathComponent(programFiles, isDirectory: true),
                                       to: &roots, seen: &seen, fileManager: fileManager)
                }
            }
        }
        return roots
    }

    private static func addGameDirectories(in programs: URL, to roots: inout [URL],
                                          seen: inout Set<String>, fileManager: FileManager) {
        guard let names = try? fileManager.contentsOfDirectory(atPath: programs.path) else { return }
        for name in names.prefix(128) {
            let normalized = name.lowercased().replacingOccurrences(of: " ", with: "")
            guard normalized.contains("rockraiders") || normalized.contains("legorr") else { continue }
            let root = programs.appendingPathComponent(name, isDirectory: true).standardizedFileURL
            let path = root.path
            if seen.insert(path).inserted { roots.append(root) }
        }
    }

    private static func resolveCaseInsensitive(root: URL, components: [String],
                                               fileManager: FileManager) -> URL? {
        guard !components.isEmpty else { return nil }
        var directory = root
        for component in components {
            guard let children = try? fileManager.contentsOfDirectory(atPath: directory.path),
                  let name = children.first(where: { $0 == component }) ??
                             children.first(where: { $0.caseInsensitiveCompare(component) == .orderedSame })
            else { return nil }
            directory.appendPathComponent(name)
        }
        return directory
    }
}

/// RRU Music Fix uses Music/Track00...Track98.ogg. Native playback accepts
/// converted equivalents; OGG is discovered separately to explain conversion.
struct OriginalMissionTrackLocator {
    static func locate(beside wad: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser,
                       extraRoot: URL? = nil, bundledRoot: URL? = nil) -> (playable: [URL], ogg: [URL]) {
        let fm = FileManager.default
        let install = wad.deletingLastPathComponent()
        let cache = home.appendingPathComponent("Library/Application Support/RockRaidersNativeMenu/ConvertedMedia")
        let roots = [install, install.deletingLastPathComponent(), cache]
            + OriginalAudioFileLocator.automaticAudioRoots(home: home)
            + (extraRoot.map { [$0] } ?? [])
        var folders = (bundledRoot.map { [$0.appendingPathComponent("Music")] } ?? []) + [cache, cache.appendingPathComponent("Music"), home.appendingPathComponent("Downloads/Rock-Raiders-Mission-Music-Mac/Music")]
        if let extraRoot { folders.append(extraRoot) }
        for root in roots {
            if let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
                folders += entries.filter { $0.lastPathComponent.lowercased() == "music" }
            }
        }
        var playable: [URL] = [], ogg: [URL] = []
        var playableNames = Set<String>()
        var seen = Set<String>()
        for folder in folders {
            let entries = (try? fm.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])) ?? []
            for file in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.deletingPathExtension().lastPathComponent.lowercased()
                guard name.count == 7, name.hasPrefix("track"),
                      let number = Int(name.suffix(2)), (0...98).contains(number),
                      let info = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      info.isRegularFile == true, let size = info.fileSize,
                      (1...100_000_000).contains(size),
                      seen.insert(file.standardizedFileURL.path).inserted else { continue }
                switch file.pathExtension.lowercased() {
                case "wav", "m4a", "mp3", "aif", "aiff":
                    if playableNames.insert(name).inserted { playable.append(file) }
                case "ogg": ogg.append(file)
                default: break
                }
            }
        }
        return (playable, ogg)
    }
}
