import Foundation

@main struct OriginalAudioFileLocatorTests {
    // Directory enumeration can return URLs with a different base URL, and
    // macOS temporary paths can use /var or /private/var. Compare canonical
    // file paths, not URL representation; distinct fallback files stay distinct.
    private static func canonicalPath(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private static func isSameFile(_ actual: URL?, as expected: URL) -> Bool {
        actual.map(canonicalPath) == canonicalPath(expected)
    }

    static func main() throws {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(
            "openlrr-audio-locator-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let installed = temp.appendingPathComponent("Rock Raiders", isDirectory: true)
        let sounds = installed.appendingPathComponent("Data/Sounds", isDirectory: true)
        let streamed = sounds.appendingPathComponent("Streamed", isDirectory: true)
        try fm.createDirectory(at: streamed, withIntermediateDirectories: true)
        let wav = sounds.appendingPathComponent("Atmosdel.WAV")
        let streamWav = streamed.appendingPathComponent("OriginalAmbient.WaV")
        try Data(repeating: 0, count: 44).write(to: wav)
        try Data(repeating: 0, count: 44).write(to: streamWav)
        let wad = installed.appendingPathComponent("LegoRR0.wad")
        let nestedWad = installed.appendingPathComponent("Data/LegoRR0.wad")
        // The locator never reads or requires the WAD itself, only its position.
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds\\ATmosDel.wav", beside: wad), as: wav))
        precondition(isSameFile(OriginalAudioFileLocator.locate("sounds/streamed/originalambient.wav",
                                                     beside: nestedWad), as: streamWav))
        precondition(isSameFile(OriginalAudioFileLocator.locate("Data/Sounds/Atmosdel.wav",
                                                     beside: wad), as: wav))

        // A downloaded folder explicitly selected by the user can contain
        // Data/Sounds, Sounds, or the file itself beneath its Sounds directory.
        let selectedSounds = temp.appendingPathComponent("Audio Download/Sounds", isDirectory: true)
        try fm.createDirectory(at: selectedSounds, withIntermediateDirectories: true)
        let extra = selectedSounds.appendingPathComponent("MenuTheme.wav")
        try Data(repeating: 0, count: 44).write(to: extra)
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds/MenuTheme.wav",
                  beside: wad, additionalRoot: selectedSounds), as: extra))

        // RRU audio ZIPs can contain WAVs directly, without Sounds/Streamed.
        let extracted = temp.appendingPathComponent("Atmosdel_and_Stats", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let replacement = extracted.appendingPathComponent("Atmosdel.wav")
        try Data(repeating: 0, count: 44).write(to: replacement)
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds/Streamed/Atmosdel.wav",
                  beside: wad, additionalRoot: extracted), as: replacement))

        // If WADs were copied to Downloads, selecting the original game
        // installation directory should still discover its streamed audio.
        let copiedWad = temp.appendingPathComponent("Downloads/LegoRR0.wad")
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds/Streamed/OriginalAmbient.wav",
                  beside: copiedWad, additionalRoot: installed), as: streamWav))

        // When someone opens a copied WAD, the original audio may already
        // exist in their Wineskin wrapper. No second user selection is needed.
        let home = temp.appendingPathComponent("ExampleHome", isDirectory: true)
        let game = home.appendingPathComponent(
            "Applications/Sikarugir/Rock Raiders.app/Contents/SharedSupport/prefix/drive_c/Program Files/Rock Raiders Original",
            isDirectory: true)
        let wrappedSounds = game.appendingPathComponent("Data/Sounds/Streamed", isDirectory: true)
        try fm.createDirectory(at: wrappedSounds, withIntermediateDirectories: true)
        let wrappedWav = wrappedSounds.appendingPathComponent("Atmosdel.wav")
        try Data(repeating: 0, count: 44).write(to: wrappedWav)
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds/Streamed/Atmosdel.wav",
            beside: copiedWad, homeDirectory: home), as: wrappedWav))

        // The RRU replacement archive may already be extracted in Downloads.
        let rruExtract = home.appendingPathComponent("Downloads/Atmosdel_and_Stats", isDirectory: true)
        try fm.createDirectory(at: rruExtract, withIntermediateDirectories: true)
        let rruWav = rruExtract.appendingPathComponent("Stats.wav")
        try Data(repeating: 0, count: 44).write(to: rruWav)
        precondition(isSameFile(OriginalAudioFileLocator.locate("Sounds/Streamed/Stats.wav",
            beside: copiedWad, homeDirectory: home), as: rruWav))

        // Keep searching when a nearby CAB-extracted file is corrupted.
        // The original game often shipped unreadable copies of Atmosdel.wav.
        let broken = copiedWad.deletingLastPathComponent()
            .appendingPathComponent("Data/Sounds/Streamed/Atmosdel.wav")
        try fm.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 44).write(to: broken)
        let choices = OriginalAudioFileLocator.locateAll("Sounds/Streamed/Atmosdel.wav",
                    beside: copiedWad, homeDirectory: home)
        precondition(choices.count >= 2 && isSameFile(choices.first, as: broken))
        precondition(choices.contains { isSameFile($0, as: wrappedWav) })

        let musicFolder = installed.appendingPathComponent("mUsIc")
        try fm.createDirectory(at: musicFolder, withIntermediateDirectories: true)
        for name in ["Track00.ogg", "Track01.m4a", "Atmosdel.wav", "Track99.wav"] {
            try Data([1, 2, 3]).write(to: musicFolder.appendingPathComponent(name))
        }
        let missionTracks = OriginalMissionTrackLocator.locate(beside: wad, home: home)
        precondition(missionTracks.playable.map { $0.lastPathComponent } == ["Track01.m4a"])
        precondition(missionTracks.ogg.map { $0.lastPathComponent } == ["Track00.ogg"])

        let bundle = temp.appendingPathComponent("Native.app/Contents/Resources")
        let bundledMusic = bundle.appendingPathComponent("Music")
        try fm.createDirectory(at: bundledMusic, withIntermediateDirectories: true)
        let bundledTrack = bundledMusic.appendingPathComponent("Track10.m4a")
        let installedTrack = musicFolder.appendingPathComponent("Track10.m4a")
        try Data([1, 2, 3]).write(to: bundledTrack)
        try Data([4, 5, 6]).write(to: installedTrack)
        let withBundle = OriginalMissionTrackLocator.locate(beside: wad, home: home, bundledRoot: bundle)
        precondition(isSameFile(withBundle.playable.first, as: bundledTrack))
        precondition(withBundle.playable.filter { $0.lastPathComponent == "Track10.m4a" }
            .map(canonicalPath) == [bundledTrack, installedTrack].map(canonicalPath))
        precondition(withBundle.playable.contains { $0.lastPathComponent == "Track01.m4a" })

        let downloadedMusic = home.appendingPathComponent("Downloads/Rock-Raiders-Mission-Music-Mac/Music")
        try fm.createDirectory(at: downloadedMusic, withIntermediateDirectories: true)
        let downloadedTrack = downloadedMusic.appendingPathComponent("Track12.m4a")
        try Data([1, 2, 3]).write(to: downloadedTrack)
        precondition(OriginalMissionTrackLocator.locate(beside: wad, home: home)
            .playable.contains { isSameFile($0, as: downloadedTrack) })

        let patch = home.appendingPathComponent("Downloads/Rock Raiders Soundtrack Patch/Data/Music")
        try fm.createDirectory(at: patch, withIntermediateDirectories: true)
        let patchTrack = patch.appendingPathComponent("Track11.wav")
        try Data([1, 2, 3]).write(to: patchTrack)
        precondition(OriginalMissionTrackLocator.locate(beside: wad, home: home)
            .playable.contains { isSameFile($0, as: patchTrack) })

        // The documented LRR_Music_Fix.zip extraction has no "rock", "raider",
        // or "soundtrack" in its folder name. Discover its OGG originals even
        // before conversion, then keep them alongside the playable variants.
        let rruMusic = home.appendingPathComponent("Downloads/LRR_Music_Fix/Music")
        try fm.createDirectory(at: rruMusic, withIntermediateDirectories: true)
        let originalTrack = rruMusic.appendingPathComponent("Track02.ogg")
        try Data([1, 2, 3]).write(to: originalTrack)
        let beforeConversion = OriginalMissionTrackLocator.locate(beside: wad, home: home)
        precondition(beforeConversion.ogg.contains { isSameFile($0, as: originalTrack) })
        precondition(!beforeConversion.playable.contains { isSameFile($0, as: originalTrack) })

        let convertedTrack = rruMusic.appendingPathComponent("Track02.m4a")
        let convertedWave = rruMusic.appendingPathComponent("Track02.wav")
        for file in [convertedTrack, convertedWave] {
            try Data([4, 5, 6]).write(to: file)
        }
        // Still reject out-of-range tracks, non-track files and non-audio files.
        for name in ["Track99.ogg", "Track99.m4a", "Track100.wav", "Track02.dll", "Atmosdel.wav"] {
            try Data([1, 2, 3]).write(to: rruMusic.appendingPathComponent(name))
        }
        // The named exception must not broaden discovery to arbitrary download
        // folders or recurse beyond the existing fixed package suffixes.
        for path in ["Downloads/LRR_Music_Fix_Unrelated/Music",
                     "Downloads/Unrelated/Music", "Downloads/LRR_Music_Fix/Nested/Music"] {
            let ignored = home.appendingPathComponent(path)
            try fm.createDirectory(at: ignored, withIntermediateDirectories: true)
            for name in ["Track20.m4a", "Track20.ogg"] {
                try Data([1, 2, 3]).write(to: ignored.appendingPathComponent(name))
            }
        }
        let afterConversion = OriginalMissionTrackLocator.locate(beside: wad, home: home)
        precondition(afterConversion.playable.map(canonicalPath).sorted() ==
            (beforeConversion.playable + [convertedTrack, convertedWave]).map(canonicalPath).sorted())
        precondition(afterConversion.playable.filter { $0.deletingPathExtension().lastPathComponent == "Track02" }
            .map(canonicalPath) == [convertedTrack, convertedWave].map(canonicalPath))
        precondition(afterConversion.ogg.map(canonicalPath).sorted() ==
            beforeConversion.ogg.map(canonicalPath).sorted())

        // Archive extraction names are matched case-insensitively on hosts
        // whose filesystems distinguish case as well as on typical macOS.
        // Use an intermediate path so case-insensitive filesystems do not see
        // the destination of a case-only move as an already-existing folder.
        let renamedPackage = temp.appendingPathComponent("RenamingArchive")
        let lowercasedPackage = home.appendingPathComponent("Downloads/lrr_music_fix")
        try fm.moveItem(at: rruMusic.deletingLastPathComponent(), to: renamedPackage)
        try fm.moveItem(at: renamedPackage, to: lowercasedPackage)
        let lowercasedTracks = OriginalMissionTrackLocator.locate(beside: wad, home: home)
        precondition(lowercasedTracks.ogg.contains {
            isSameFile($0, as: lowercasedPackage.appendingPathComponent("Music/Track02.ogg"))
        })
        precondition(lowercasedTracks.playable.contains {
            isSameFile($0, as: lowercasedPackage.appendingPathComponent("Music/Track02.m4a"))
        })

        // Do not follow traversal or arbitrary formats from untrusted CFG.
        precondition(OriginalAudioFileLocator.locate("../Sounds/Atmosdel.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("/etc/passwd.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds\\Atmosdel.ogg", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds/doesnotexist.wav", beside: wad) == nil)
        print("PASS: original loose audio discovery, custom folder, case-insensitive lookup, unsafe path rejection")
    }
}
