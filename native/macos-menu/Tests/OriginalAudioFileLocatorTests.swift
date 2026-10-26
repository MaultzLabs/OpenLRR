import Foundation

@main struct OriginalAudioFileLocatorTests {
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
        precondition(OriginalAudioFileLocator.locate("Sounds\\ATmosDel.wav", beside: wad) == wav)
        precondition(OriginalAudioFileLocator.locate("sounds/streamed/originalambient.wav",
                                                     beside: nestedWad) == streamWav)
        precondition(OriginalAudioFileLocator.locate("Data/Sounds/Atmosdel.wav",
                                                     beside: wad) == wav)

        // A downloaded folder explicitly selected by the user can contain
        // Data/Sounds, Sounds, or the file itself beneath its Sounds directory.
        let selectedSounds = temp.appendingPathComponent("Audio Download/Sounds", isDirectory: true)
        try fm.createDirectory(at: selectedSounds, withIntermediateDirectories: true)
        let extra = selectedSounds.appendingPathComponent("MenuTheme.wav")
        try Data(repeating: 0, count: 44).write(to: extra)
        precondition(OriginalAudioFileLocator.locate("Sounds/MenuTheme.wav",
                  beside: wad, additionalRoot: selectedSounds) == extra)

        // RRU audio ZIPs can contain WAVs directly, without Sounds/Streamed.
        let extracted = temp.appendingPathComponent("Atmosdel_and_Stats", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        let replacement = extracted.appendingPathComponent("Atmosdel.wav")
        try Data(repeating: 0, count: 44).write(to: replacement)
        precondition(OriginalAudioFileLocator.locate("Sounds/Streamed/Atmosdel.wav",
                  beside: wad, additionalRoot: extracted) == replacement)

        // If WADs were copied to Downloads, selecting the original game
        // installation directory should still discover its streamed audio.
        let copiedWad = temp.appendingPathComponent("Downloads/LegoRR0.wad")
        precondition(OriginalAudioFileLocator.locate("Sounds/Streamed/OriginalAmbient.wav",
                  beside: copiedWad, additionalRoot: installed) == streamWav)

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
        precondition(OriginalAudioFileLocator.locate("Sounds/Streamed/Atmosdel.wav",
            beside: copiedWad, homeDirectory: home) == wrappedWav)

        // The RRU replacement archive may already be extracted in Downloads.
        let rruExtract = home.appendingPathComponent("Downloads/Atmosdel_and_Stats", isDirectory: true)
        try fm.createDirectory(at: rruExtract, withIntermediateDirectories: true)
        let rruWav = rruExtract.appendingPathComponent("Stats.wav")
        try Data(repeating: 0, count: 44).write(to: rruWav)
        precondition(OriginalAudioFileLocator.locate("Sounds/Streamed/Stats.wav",
            beside: copiedWad, homeDirectory: home) == rruWav)

        // Keep searching when a nearby CAB-extracted file is corrupted.
        // The original game often shipped unreadable copies of Atmosdel.wav.
        let broken = copiedWad.deletingLastPathComponent()
            .appendingPathComponent("Data/Sounds/Streamed/Atmosdel.wav")
        try fm.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0, count: 44).write(to: broken)
        let choices = OriginalAudioFileLocator.locateAll("Sounds/Streamed/Atmosdel.wav",
                    beside: copiedWad, homeDirectory: home)
        precondition(choices.count >= 2 && choices.first == broken)
        precondition(choices.contains(wrappedWav))

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
        try Data([1, 2, 3]).write(to: bundledTrack)
        try Data([4, 5, 6]).write(to: musicFolder.appendingPathComponent("Track10.m4a"))
        let withBundle = OriginalMissionTrackLocator.locate(beside: wad, home: home, bundledRoot: bundle)
        precondition(withBundle.playable.first == bundledTrack)
        precondition(withBundle.playable.filter { $0.lastPathComponent == "Track10.m4a" }.count == 1)
        precondition(withBundle.playable.contains { $0.lastPathComponent == "Track01.m4a" })

        let downloadedMusic = home.appendingPathComponent("Downloads/Rock-Raiders-Mission-Music-Mac/Music")
        try fm.createDirectory(at: downloadedMusic, withIntermediateDirectories: true)
        let downloadedTrack = downloadedMusic.appendingPathComponent("Track12.m4a")
        try Data([1, 2, 3]).write(to: downloadedTrack)
        precondition(OriginalMissionTrackLocator.locate(beside: wad, home: home).playable.contains(downloadedTrack))

        // Do not follow traversal or arbitrary formats from untrusted CFG.
        precondition(OriginalAudioFileLocator.locate("../Sounds/Atmosdel.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("/etc/passwd.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds\\Atmosdel.ogg", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds/doesnotexist.wav", beside: wad) == nil)
        print("PASS: original loose audio discovery, custom folder, case-insensitive lookup, unsafe path rejection")
    }
}
