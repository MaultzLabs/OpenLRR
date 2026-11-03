#if os(macOS)
import AVFoundation
import Foundation

/// Plays only original SFX_Drill / SFX_DrillFade (or the original Pilot stats
/// overrides) from the selected user's WAD/loose installation. This does not
/// synthesize, install, redistribute or bundle audio. Native 3-D positioning,
/// random sample groups and sound-distance attenuation still need parity work.
final class OriginalDrillAudio {
    private let config: LegoConfig
    private let resources: GameResources
    private let wadURL: URL?
    private let extraRoot: URL?
    private let stats: OriginalDrillStats
    private let soundEnabled: Bool
    private var loops: [String: AVAudioPlayer] = [:]
    private var fadePlayers: [String: AVAudioPlayer] = [:]

    init(config: LegoConfig, resources: GameResources, wadURL: URL?, extraRoot: URL?) {
        self.config = config
        self.resources = resources
        self.wadURL = wadURL
        self.extraRoot = extraRoot
        stats = OriginalDrillStats(config: config)
        let flag = config.valueUnderGame(["Main", "SoundOn"])?.uppercased() ?? "TRUE"
        soundEnabled = !["FALSE", "NO", "OFF", "0"].contains(flag)
    }

    private func player(named identifier: String) -> AVAudioPlayer? {
        guard soundEnabled,
              let sample = try? SoundSampleCatalog(config: config).samples(named: identifier).first
        else { return nil }
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

    func pause() {
        for audio in loops.values { audio.pause() }
        for audio in fadePlayers.values { audio.pause() }
    }

    func resume() {
        for audio in loops.values where audio.currentTime < audio.duration { audio.play() }
        for audio in fadePlayers.values where audio.currentTime < audio.duration { audio.play() }
    }

    func stopAll() {
        for audio in loops.values { audio.stop() }
        for audio in fadePlayers.values { audio.stop() }
        loops.removeAll()
        fadePlayers.removeAll()
    }

    deinit { stopAll() }
}
#endif
