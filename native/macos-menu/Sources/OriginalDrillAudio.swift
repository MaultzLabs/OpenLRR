#if os(macOS)
import AVFoundation
import Foundation

/// Plays original SFX_RockBreak and SFX_Drill / SFX_DrillFade (or the Pilot stats
/// overrides) from the selected user's WAD/loose installation. This does not
/// synthesize, install, redistribute or bundle audio. Native 3-D positioning,
/// drill sample-group selection and sound-distance attenuation still need parity work.
final class OriginalDrillAudio {
    private let config: LegoConfig
    private let resources: GameResources
    private let wadURL: URL?
    private let extraRoot: URL?
    private let stats: OriginalDrillStats
    private let soundEnabled: Bool
    private var loops: [String: AVAudioPlayer] = [:]
    private var fadePlayers: [String: AVAudioPlayer] = [:]
    private var rockBreakPlayers: [AVAudioPlayer] = []
    private var paused = false

    init(config: LegoConfig, resources: GameResources, wadURL: URL?, extraRoot: URL?) {
        self.config = config
        self.resources = resources
        self.wadURL = wadURL
        self.extraRoot = extraRoot
        stats = OriginalDrillStats(config: config)
        let flag = config.valueUnderGame(["Main", "SoundOn"])?.uppercased() ?? "TRUE"
        soundEnabled = !["FALSE", "NO", "OFF", "0"].contains(flag)
    }

    private func player(named identifier: String, randomVariant: Bool = false) -> AVAudioPlayer? {
        guard soundEnabled else { return nil }
        let catalog = SoundSampleCatalog(config: config)
        let sample: SoundSampleCatalog.Sample?
        if randomVariant {
            sample = try? catalog.randomSample(named: identifier)
        } else {
            sample = (try? catalog.samples(named: identifier))?.first
        }
        guard let sample else { return nil }
        let path = sample.wavPath.replacingOccurrences(of: "\\", with: "/")
        var candidate: AVAudioPlayer?
        if let wadURL {
            for url in OriginalAudioFileLocator.locateAll(path, beside: wadURL, additionalRoot: extraRoot) {
                if let decoded = try? AVAudioPlayer(contentsOf: url) {
                    candidate = decoded
                    break
                }
            }
        }
        if candidate == nil, resources.exists(path),
           let data = try? resources.data(at: path, maximumBytes: 50_000_000) {
            candidate = try? AVAudioPlayer(data: data)
        }
        guard let candidate else { return nil }
        candidate.volume = Float(pow(10.0, Double(sample.volume) / 2000.0))
        return candidate
    }

    func start(raiderID: String) {
        guard soundEnabled else { return }
        loops.removeValue(forKey: raiderID)?.stop()
        fadePlayers.removeValue(forKey: raiderID)?.stop()
        guard let player = player(named: stats.soundIdentifier(fade: false)) else { return }
        player.numberOfLoops = -1
        guard player.prepareToPlay(), player.play() else { return }
        loops[raiderID] = player
    }

    func stop(raiderID: String, playFade: Bool) {
        loops.removeValue(forKey: raiderID)?.stop()
        fadePlayers.removeValue(forKey: raiderID)?.stop()
        guard playFade, let fade = player(named: stats.soundIdentifier(fade: true)) else { return }
        fade.numberOfLoops = 0
        guard fade.prepareToPlay(), fade.play() else { return }
        fadePlayers[raiderID] = fade
    }

    /// Game.cpp::Lego_PTL_RockFall plays this configured one-shot before
    /// trying to spawn the effect, even if the animation cannot be loaded.
    /// Spatial playback and original simultaneous-buffer limits remain open.
    func playRockBreak() {
        guard !paused, soundEnabled else { return }
        rockBreakPlayers.removeAll { !$0.isPlaying }
        // Bound concurrent native players; do not interrupt an existing sound.
        guard rockBreakPlayers.count < 32,
              let audio = player(named: "SFX_RockBreak", randomVariant: true) else { return }
        audio.numberOfLoops = 0
        guard audio.prepareToPlay(), audio.play() else { return }
        rockBreakPlayers.append(audio)
    }

    func pause() {
        guard !paused else { return }
        paused = true
        // Completed AVAudioPlayers can reset currentTime to zero. Do not
        // restart a finished rockfall sound when dismissing a tutorial panel.
        rockBreakPlayers.removeAll { !$0.isPlaying }
        for audio in rockBreakPlayers { audio.pause() }
        for audio in loops.values { audio.pause() }
        for audio in fadePlayers.values { audio.pause() }
    }

    func resume() {
        guard paused else { return }
        paused = false
        for audio in rockBreakPlayers { audio.play() }
        for audio in loops.values where audio.currentTime < audio.duration { audio.play() }
        for audio in fadePlayers.values where audio.currentTime < audio.duration { audio.play() }
    }

    func stopAll() {
        for audio in rockBreakPlayers { audio.stop() }
        rockBreakPlayers.removeAll()
        for audio in loops.values { audio.stop() }
        for audio in fadePlayers.values { audio.stop() }
        loops.removeAll()
        fadePlayers.removeAll()
    }

    deinit { stopAll() }
}
#endif
