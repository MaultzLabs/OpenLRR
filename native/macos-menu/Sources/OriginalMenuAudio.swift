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
               additionalAudioRoot: URL? = nil, sampleName: String = "SFX_AmbientMusicLoop") -> String {
        stop()

        if let enabled = (config.valueUnderGame(["Main", "SoundOn"]) ??
                          config.value("LegoRR", "SoundOn") ??
                          config.valueUnderGame(["SoundOn"]))?.uppercased(),
           ["FALSE", "NO", "OFF", "0"].contains(enabled) {
            return "SoundOn is disabled in Lego.cfg"
        }

        let configured = try? SoundSampleCatalog(config: config)
            .samples(named: sampleName)

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

        if sampleName != "SFX_AmbientMusicLoop" {
            return "Original cave ambience unavailable: \(sampleName)"
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

    func stop() {
        player?.stop()
        player = nil
    }

    func configure(config: LegoConfig, resources: GameResources,
                   beside wadURL: URL, extraAudioRoot: URL? = nil, sampleName: String = "SFX_Okay") {
        stop()
        // The same SoundOn setting governs SFX and menu ambience.
        if let flag = (config.valueUnderGame(["Main", "SoundOn"]) ??
                          config.value("LegoRR", "SoundOn") ??
                       config.valueUnderGame(["SoundOn"]))?.uppercased(),
           ["FALSE", "NO", "OFF", "0"].contains(flag) { return }
        let samples = try? SoundSampleCatalog(config: config).samples(named: sampleName)
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

/// Gameplay CD music is separate from SFX_AmbientMusicLoop.
/// Game.cpp Lego_SetMusicPlaying uses SoundMode::Once and selects the next
/// track on completion. Only explicitly selected user-owned tracks are read.
final class OriginalMissionAudio: NSObject, AVAudioPlayerDelegate {
    private let defaultsKey = "OriginalMissionSoundtrackPaths.v2"
    var onStatus: ((String) -> Void)?
    private(set) var playbackStatus = "Mission music stopped"
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "NativeMissionMusicEnabled.v1") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "NativeMissionMusicEnabled.v1") }
    }
    private func report(_ message: String) {
        playbackStatus = message
        onStatus?(message)
    }
    private var player: AVAudioPlayer?
    private let session = OriginalMissionMusicSession()
    private var attempt: OriginalMissionMusicSession.Attempt?

    func setTracks(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map { $0.path }, forKey: defaultsKey)
    }

    func stop() {
        session.stop()
        discardPlayer()
    }

    @discardableResult
    func start(config: LegoConfig, beside wad: URL, extraRoot: URL?) -> String {
        stop()
        // Native file playback has its own visible preference, independent of
        // the legacy CD-device MusicOn setting. Never re-enable it on restart.
        guard enabled else { report("Mission music off"); return playbackStatus }
        let selected = (UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
            .map { URL(fileURLWithPath: $0) }
        let discovered = OriginalMissionTrackLocator.locate(beside: wad, extraRoot: extraRoot, bundledRoot: Bundle.main.resourceURL)
        play(session.start(selected: selected, discovered: discovered.playable))
        if player != nil || !session.failures.isEmpty { return playbackStatus }
        if !discovered.ogg.isEmpty { report("OGG music needs conversion; select the installed M4A tracks with Mission Music…") }
        else { report("No mission tracks found. Use Mission Music… to select original soundtrack files.") }
        return playbackStatus
    }

    private func discardPlayer() {
        player?.delegate = nil
        player?.stop()
        player = nil
        attempt = nil
    }

    private func play(_ first: OriginalMissionMusicSession.Attempt?) {
        discardPlayer()
        var candidate = first
        // No recursion: each failure consumes one unique file for this session.
        while let current = candidate {
            let next: AVAudioPlayer
            do { next = try AVAudioPlayer(contentsOf: current.url) }
            catch {
                candidate = session.finished(current, error: error.localizedDescription)
                continue
            }
            guard next.duration.isFinite, next.duration > 0 else {
                candidate = session.finished(current, error: "empty or invalid audio duration")
                continue
            }
            next.numberOfLoops = 0
            next.volume = 1
            next.delegate = self
            player = next
            attempt = current
            guard next.prepareToPlay(), next.play() else {
                discardPlayer()
                candidate = session.finished(current, error: "audio output would not start")
                continue
            }
            let skipped = session.failures.isEmpty ? "" : " • \(session.failures.count) unavailable file(s) skipped"
            report("Playing \(current.url.lastPathComponent) • \(session.availableTrackCount) mission tracks" + skipped)
            return
        }
        if !session.failures.isEmpty {
            report("Music could not play: " + session.failures.map {
                "\($0.url.lastPathComponent): \($0.reason)"
            }.joined(separator: "; "))
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard self.player === player, let attempt else { return }
        play(session.finished(attempt, error: flag ? nil : "playback stopped unexpectedly"))
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        guard self.player === player, let attempt else { return }
        play(session.finished(attempt, error: "decode error: " + (error?.localizedDescription ?? "unknown audio error")))
    }
}

#endif

#if os(macOS)
/// Original Chief samples are one-shot speech, separate from mission music.
final class OriginalNERPsAudio {
    private var player: AVAudioPlayer?
    func stop() { player?.stop(); player = nil }
    func start(path: String, resources: GameResources, wadURL: URL?,
               extraRoot: URL?, soundEnabled: Bool, volume: Int = 0) -> Double? {
        var candidate: AVAudioPlayer?
        if let wadURL {
            for url in OriginalAudioFileLocator.locateAll(path, beside: wadURL, additionalRoot: extraRoot) {
                if let decoded = try? AVAudioPlayer(contentsOf: url) { candidate = decoded; break }
            }
        }
        if candidate == nil, resources.exists(path),
           let data = try? resources.data(at: path, maximumBytes: 50_000_000) {
            candidate = try? AVAudioPlayer(data: data)
        }
        guard let candidate, candidate.duration.isFinite, candidate.duration >= 0 else { return nil }
        stop()
        candidate.numberOfLoops = 0
        candidate.volume = Float(pow(10.0, Double(volume) / 2000.0))
        if soundEnabled {
            candidate.prepareToPlay()
            guard candidate.play() else { return nil }
            player = candidate
        }
        // Retail still uses sample duration when sound is disabled.
        return candidate.duration
    }
    deinit { stop() }
}

/// Stream_Objective_<full level identifier>, not NERPMessageFile speech.
/// One attempt per initial briefing is enforced by the workspace startup gate.
final class OriginalMissionBriefingAudio {
    private let speech = OriginalNERPsAudio()
    func stop() { speech.stop() }
    func start(definition: OriginalMissionBriefingDefinition, config: LegoConfig?,
               resources: GameResources, wadURL: URL?, extraRoot: URL?) -> String {
        stop()
        guard let config else { return "Original briefing speech unavailable: no Lego.cfg" }
        let flag = config.valueUnderGame(["Main", "SoundOn"])?.uppercased() ?? "TRUE"
        guard !["FALSE", "NO", "OFF", "0"].contains(flag) else { return "Briefing speech off (SoundOn disabled)" }
        do {
            let samples = try SoundSampleCatalog(config: config).samples(named: definition.speechSampleName)
            for sample in samples {
                if speech.start(path: sample.wavPath, resources: resources, wadURL: wadURL,
                                extraRoot: extraRoot, soundEnabled: true, volume: sample.volume) != nil {
                    return "Playing original briefing speech: \(sample.wavPath)"
                }
            }
            return "Original briefing speech missing or unplayable: \(definition.speechSampleName)"
        } catch { return "Original briefing speech unavailable: \(error)" }
    }
    deinit { stop() }
}
#endif
