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

        // Do not follow traversal or arbitrary formats from untrusted CFG.
        precondition(OriginalAudioFileLocator.locate("../Sounds/Atmosdel.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("/etc/passwd.wav", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds\\Atmosdel.ogg", beside: wad) == nil)
        precondition(OriginalAudioFileLocator.locate("Sounds/doesnotexist.wav", beside: wad) == nil)
        print("PASS: original loose audio discovery, custom folder, case-insensitive lookup, unsafe path rejection")
    }
}
