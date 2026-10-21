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
        let normalized = configuredPath.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 32,
              parts.last?.lowercased().hasSuffix(".wav") == true,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                                 !$0.contains(":") && !$0.contains("\0") }) else {
            return nil
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
                return url
            }
        }
        return nil
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
