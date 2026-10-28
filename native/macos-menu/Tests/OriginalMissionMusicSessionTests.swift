import Foundation

/// Exercises the production lifecycle using synthetic paths and delegate
/// outcomes. No game assets, audio device, AVFoundation or filesystem reads.
@main struct OriginalMissionMusicSessionTests {
    static func main() {
        alternateCopiesAndLogicalRepeats()
        selectedTracksAndDiscoveredFallback()
        failuresStayQuarantinedUntilRestart()
        lateCallbacksAndStop()
        boundedFailureAndEmptyInput()
        randomTrackChoicesNotFileChoices()
        print("PASS: mission music alternatives, failure recovery, selection priority, lifecycle and logical-track shuffle")
    }

    static func file(_ path: String) -> URL { URL(fileURLWithPath: "/synthetic/" + path) }
    static func session() -> OriginalMissionMusicSession { OriginalMissionMusicSession(randomIndex: { _ in 0 }) }

    static func alternateCopiesAndLogicalRepeats() {
        let music = session()
        let broken = file("bundle/Track10.m4a")
        let good = file("install/TRACK10.wav")
        let other = file("install/Track11.m4a")
        let first = music.start(selected: [], discovered: [broken, other, good])!
        precondition(first.url == broken && music.availableTrackCount == 2)
        let second = music.finished(first, error: "corrupt header")!
        precondition(second.url == good, "Try same-track alternatives before changing songs")
        precondition(music.failures.count == 1 && music.failures[0].url == broken)
        precondition(music.failures[0].reason == "corrupt header")
        let third = music.finished(second)!
        precondition(third.url == other, "A second copy is not a second song")
        precondition(music.finished(third)!.url == good, "Do not retry the broken copy on each song")

        // One playable track keeps playing, using a fresh callback identity.
        let single = session()
        var attempt = single.start(selected: [good], discovered: [])!
        for _ in 0..<100 {
            let next = single.finished(attempt)!
            precondition(next.url == good && next.id != attempt.id)
            attempt = next
        }
        precondition(single.isActive && single.failures.isEmpty)
    }

    static func selectedTracksAndDiscoveredFallback() {
        let music = session()
        let chosen = file("chosen/Track11.aiff")
        let chosen2 = file("chosen/Track12.aiff")
        let discovered = file("bundle/Track10.m4a")
        var attempt = music.start(selected: [chosen, chosen2], discovered: [discovered, chosen])!
        precondition(attempt.url == chosen && music.availableTrackCount == 2)
        attempt = music.finished(attempt)!
        precondition(attempt.url == chosen2, "Discovery must not override a working selection")
        attempt = music.finished(attempt, error: "mid-stream decode error")!
        precondition(attempt.url == chosen)
        attempt = music.finished(attempt, error: "output refused")!
        precondition(attempt.url == discovered && music.availableTrackCount == 1)
        for _ in 0..<10 {
            attempt = music.finished(attempt)!
            precondition(attempt.url == discovered)
        }
        precondition(music.failures.count == 2)
        precondition(music.finished(attempt, error: "last file failed") == nil)
        precondition(!music.isActive && music.current == nil && music.availableTrackCount == 0)
    }

    static func failuresStayQuarantinedUntilRestart() {
        let music = session()
        let first = file("Track10.wav")
        let second = file("Track11.wav")
        let attempt = music.start(selected: [first, second], discovered: [])!
        let next = music.finished(attempt, error: "failed after starting")!
        precondition(next.url == second)
        precondition(music.finished(next)!.url == second)
        let restarted = music.start(selected: [first, second], discovered: [])!
        precondition(restarted.url == first && music.failures.isEmpty && music.availableTrackCount == 2)
        precondition(music.finished(next, error: "late error") == nil)
        precondition(music.current == restarted && music.failures.isEmpty)
    }

    static func lateCallbacksAndStop() {
        let music = session()
        let a = file("Track10.wav"), b = file("Track11.wav")
        let old = music.start(selected: [a, b], discovered: [])!
        let next = music.finished(old, error: "first callback")!
        precondition(music.finished(old) == nil)
        precondition(music.finished(old, error: "duplicate failure callback") == nil)
        precondition(music.current == next && music.failures.count == 1)
        music.stop()
        precondition(!music.isActive && music.current == nil)
        precondition(music.finished(next) == nil)
        precondition(music.finished(next, error: "after exit") == nil)
        let restarted = music.start(selected: [a], discovered: [])!
        precondition(music.finished(old) == nil && music.current == restarted)
        music.stop()
        music.stop()
        precondition(music.current == nil && !music.isActive)
    }

    static func boundedFailureAndEmptyInput() {
        let music = session()
        let original = file("bundle/Track10.m4a")
        let samePath = file("bundle/subfolder/../Track10.m4a")
        let alternate = file("install/Track10.wav")
        let nonFile = URL(string: "https://example.invalid/Track11.wav")!
        var attempt = music.start(selected: [original, original, samePath, nonFile],
                                  discovered: [original, alternate, alternate])
        var tries = 0
        while let current = attempt {
            tries += 1
            precondition(tries <= 2, "Every unique file may fail only once, not recursively forever")
            attempt = music.finished(current, error: "synthetic failure")
        }
        precondition(tries == 2 && music.failures.count == 2 && !music.isActive)
        precondition(music.start(selected: [], discovered: []) == nil)
        precondition(music.failures.isEmpty && !music.isActive && music.availableTrackCount == 0)
        precondition(music.start(selected: [nonFile], discovered: [alternate])?.url == alternate)

        // Arbitrarily named chosen files are distinct, even with equal names.
        let chosen = [file("a/Theme.wav"), file("b/Theme.wav"), file("Track99.wav"),
                      file("other/Track99.wav"), file("Track+1.wav"), file("other/Track+1.wav")]
        _ = music.start(selected: chosen, discovered: [])
        precondition(music.availableTrackCount == chosen.count)
    }

    static func randomTrackChoicesNotFileChoices() {
        var sizes: [Int] = []
        let music = OriginalMissionMusicSession(randomIndex: { count in sizes.append(count); return count - 1 })
        let a = file("a/Track01.m4a"), copy = file("b/Track01.wav"), b = file("Track02.wav")
        let first = music.start(selected: [], discovered: [a, copy, b])!
        precondition(first.url == b && sizes == [2, 1], "Duplicate copies must not increase song probability")
        sizes = []
        let next = music.finished(first)!
        precondition(next.url == a && sizes == [1])
        precondition(music.finished(next, error: "bad copy")?.url == copy)
    }
}
