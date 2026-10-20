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
                       fileManager: FileManager = .default) -> URL? {
        let normalized = configuredPath.replacingOccurrences(of: "\\", with: "/")
        let parts = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.count <= 32,
              parts.last?.lowercased().hasSuffix(".wav") == true,
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                                 !$0.contains(":") && !$0.contains("\0") }) else {
            return nil
        }

        let wadDirectory = selectedWadURL.deletingLastPathComponent()
        let roots = [wadDirectory, wadDirectory.appendingPathComponent("Data", isDirectory: true),
                     wadDirectory.deletingLastPathComponent().appendingPathComponent("Data", isDirectory: true)] +
                    (additionalRoot.map { [$0] } ?? [])

        for root in roots {
            var candidates = [parts]
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
            if let additionalRoot, root.standardizedFileURL == additionalRoot.standardizedFileURL,
               let filename = parts.last {
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
