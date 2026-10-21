#if os(macOS)
import AVFoundation
import Foundation

/// Original front-end sound, played by macOS rather than Windows DirectSound.
/// Reads private user-owned WAVs in place; does not modify the install.
final class OriginalMenuAudio {
    private var player: AVAudioPlayer?
    var isPlaying: Bool { player?.isPlaying == true }

    func stop() {
        player?.stop()
        player = nil
    }

    private func play(_ candidate: AVAudioPlayer, volume: Int = 0) -> Bool {
        candidate.numberOfLoops = -1
        // Original DirectSound attenuation units are hundredths of a decibel.
        candidate.volume = Float(pow(10.0, Double(volume) / 2000.0))
        candidate.prepareToPlay()
        guard candidate.play() else { return false }
        player = candidate
        return true
    }

    /// The original Front_RunScreenMenuType queues SFX_AmbientMusicLoop.
    /// Its filename is read from Lego.cfg > Samples. If that resource is
    /// unavailable, check the documented original menu audio Atmosdel.wav
    /// without fabricating any sound or depending on Windows DLLs.
    @discardableResult
    func start(config: LegoConfig, resources: GameResources,
               beside selectedWadURL: URL,
               additionalAudioRoot: URL? = nil) -> String {
        stop()

        if let enabled = (config.value("LegoRR", "SoundOn") ??
                          config.valueUnderGame(["SoundOn"]))?.uppercased(),
           ["FALSE", "NO", "OFF", "0"].contains(enabled) {
            return "SoundOn is disabled in Lego.cfg"
        }

        let configured = try? SoundSampleCatalog(config: config)
            .samples(named: "SFX_AmbientMusicLoop")

        var attemptedDecoding = false
        for sample in configured ?? [] {
            let path = sample.wavPath.replacingOccurrences(of: "\\", with: "/")
            for url in OriginalAudioFileLocator.locateAll(path, beside: selectedWadURL,
                                                           additionalRoot: additionalAudioRoot) {
                attemptedDecoding = true
                if let audio = try? AVAudioPlayer(contentsOf: url),
                   play(audio, volume: sample.volume) {
                    return "Playing original menu audio: \(url.lastPathComponent)"
                }
            }

            if resources.exists(path),
               let data = try? resources.data(at: path, maximumBytes: 50_000_000) {
                attemptedDecoding = true
                if let audio = try? AVAudioPlayer(data: data),
                   play(audio, volume: sample.volume) {
                    return "Playing original menu audio from WAD: \(urlFilename(path))"
                }
            }
        }

        // RRU identifies this as the main-menu recording in loose Data/Sounds.
        // Unlike the CD soundtrack it is already a WAV and needs no conversion.
        for candidate in ["Sounds/Streamed/Atmosdel.wav", "Sounds/Atmosdel.wav"] {
            for url in OriginalAudioFileLocator.locateAll(candidate,
                                      beside: selectedWadURL, additionalRoot: additionalAudioRoot) {
                attemptedDecoding = true
                if let audio = try? AVAudioPlayer(contentsOf: url), play(audio) {
                    return "Playing original menu audio: \(url.lastPathComponent)"
                }
            }
        }

        if attemptedDecoding {
            return "Original WAVs were found but none could play (possibly corrupted). Restore authentic audio from your game CD or RRU."
        }
        let expected = configured?.first?.wavPath ?? "Sounds/Streamed/Atmosdel.wav"
        return "Original menu WAV missing: \(urlFilename(expected)) (searched game installs and Downloads)"
    }

    private func urlFilename(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last
            .map(String.init) ?? raw
    }
}

/// Plays the retail SFX_Okay cue when a front-end item is activated.
/// Front_Menu_UpdateMenuItemsInput calls SFX_Random_PlaySoundNormal(SFX_Okay)
/// on selection, independent of the looping AmbientMusicLoop stream.
/// Original bytes are loaded from the user's WAD or existing installation,
/// not generated or bundled with the app.
final class OriginalMenuButtonAudio {
    private var player: AVAudioPlayer?

    func configure(config: LegoConfig, resources: GameResources,
                   beside wadURL: URL, extraAudioRoot: URL? = nil) {
        player?.stop()
        player = nil
        let samples = try? SoundSampleCatalog(config: config).samples(named: "SFX_Okay")
        guard let sample = samples?.first else { return }
        let filename = sample.wavPath
        let decibels = Float(pow(10.0, Double(sample.volume) / 2000.0))
        let urls = OriginalAudioFileLocator.locateAll(filename,
                        beside: wadURL, additionalRoot: extraAudioRoot)
        for url in urls {
            if let audio = try? AVAudioPlayer(contentsOf: url) {
                audio.volume = decibels
                audio.numberOfLoops = 0
                audio.prepareToPlay()
                player = audio
                return
            }
        }
        guard resources.exists(filename),
              let data = try? resources.data(at: filename, maximumBytes: 5_000_000),
              let audio = try? AVAudioPlayer(data: data) else { return }
        audio.volume = decibels
        audio.numberOfLoops = 0
        audio.prepareToPlay()
        player = audio
    }

    func play() {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

#endif
