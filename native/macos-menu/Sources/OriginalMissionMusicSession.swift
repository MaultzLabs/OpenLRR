import Foundation

/// Portable lifecycle for native playback of the user's original soundtrack.
/// Lego_CDTrackPlayNextCallback starts another one-shot track when music ends
/// (Game.cpp:2899–2920). File alternatives and bounded failure recovery are
/// native adaptations, not emulation of the Music Fix DLL's CD-track mapping.
final class OriginalMissionMusicSession {
    struct Attempt: Equatable {
        let id = UUID()
        let url: URL
    }
    struct Failure {
        let url: URL
        let reason: String
    }
    private struct Track {
        let key: String
        var files: [URL]
    }

    private let randomIndex: (Int) -> Int
    private var primary: [Track] = []
    private var fallback: [Track] = []
    private var pending: [URL] = []
    private var failedPaths: Set<String> = []
    private var previousTrack: String?
    private(set) var current: Attempt?
    private(set) var failures: [Failure] = []
    private(set) var isActive = false

    init(randomIndex: @escaping (Int) -> Int = { Int.random(in: 0..<$0) }) {
        self.randomIndex = randomIndex
    }

    /// Explicit selections take precedence; discovery is a fallback only when
    /// every selected file has failed. Restarting permits repaired files again.
    @discardableResult
    func start(selected: [URL], discovered: [URL]) -> Attempt? {
        stop()
        failedPaths = []
        failures = []
        previousTrack = nil
        var seen: Set<String> = []
        primary = tracks(from: selected.isEmpty ? discovered : selected, seen: &seen)
        fallback = selected.isEmpty ? [] : tracks(from: discovered, seen: &seen)
        isActive = true
        pending = candidates()
        return takeNext()
    }

    func stop() {
        isActive = false
        current = nil
        pending = []
    }

    /// A failed decode/output start/finish quarantines this file for the rest
    /// of the session, then tries its next copy in the same selection tier
    /// before another song. Successful
    /// completion begins a fresh random choice. IDs reject late callbacks from
    /// a stopped, replaced, failed, or previously completed player.
    @discardableResult
    func finished(_ attempt: Attempt, error: String? = nil) -> Attempt? {
        guard isActive, current?.id == attempt.id else { return nil }
        if let error {
            failedPaths.insert(path(attempt.url))
            failures.append(Failure(url: attempt.url, reason: error))
        } else {
            previousTrack = trackKey(attempt.url)
            pending = candidates()
        }
        return takeNext()
    }

    var availableTrackCount: Int {
        let selected = primary.filter { $0.files.contains { !failedPaths.contains(path($0)) } }
        if !selected.isEmpty { return selected.count }
        return fallback.filter { $0.files.contains { !failedPaths.contains(path($0)) } }.count
    }

    private func takeNext() -> Attempt? {
        while !pending.isEmpty {
            let url = pending.removeFirst()
            guard !failedPaths.contains(path(url)) else { continue }
            let attempt = Attempt(url: url)
            current = attempt
            return attempt
        }
        stop()
        return nil
    }

    private func candidates() -> [URL] {
        ordered(primary) + ordered(fallback)
    }

    private func ordered(_ tracks: [Track]) -> [URL] {
        var pool = tracks.filter { $0.key != previousTrack }
        var ordered: [Track] = []
        while !pool.isEmpty { ordered.append(pool.remove(at: randomIndex(pool.count))) }
        // Retain the existing native no-immediate-repeat policy, but apply it
        // to TrackNN rather than treating each M4A/WAV/cached copy as a song.
        ordered += tracks.filter { $0.key == previousTrack }
        return ordered.flatMap(\.files).filter { !failedPaths.contains(path($0)) }
    }

    private func tracks(from urls: [URL], seen: inout Set<String>) -> [Track] {
        var result: [Track] = []
        for url in urls where url.isFileURL {
            guard seen.insert(path(url)).inserted else { continue }
            let key = trackKey(url)
            if let index = result.firstIndex(where: { $0.key == key }) {
                result[index].files.append(url)
            } else {
                result.append(Track(key: key, files: [url]))
            }
        }
        return result
    }

    private func path(_ url: URL) -> String { url.standardizedFileURL.path }

    private func trackKey(_ url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        let digits = name.suffix(2)
        if name.count == 7, name.hasPrefix("track"),
           digits.allSatisfy({ $0 >= "0" && $0 <= "9" }),
           let number = Int(digits), (0...98).contains(number) { return name }
        // The picker also accepts arbitrary user-named files. Do not collapse
        // unrelated recordings merely because their basenames happen to match.
        return path(url)
    }
}
