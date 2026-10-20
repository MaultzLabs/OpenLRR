#if os(macOS)
import AVFoundation
import Foundation

/// Read-only native playback of the original front-end AmbientMusicLoop WAV.
/// The Windows winmm/OGG compatibility DLLs are not required or loaded here.
final class OriginalMenuAudio {
    private var player: AVAudioPlayer?

    func stop() {
        player?.stop()
        player = nil
    }

    /// The retail front end queues SFX_AmbientMusicLoop in a loop. Its actual
    /// filename comes from Lego.cfg -> Samples, rather than a hardcoded name.
    /// Streaming effects may live loose under Data/Sounds/Streamed next to the
    /// WADs, while regular effects often live inside the WAD archives.
    @discardableResult
    func start(config: LegoConfig, resources: GameResources,
               beside selectedWadURL: URL) -> String {
        stop()
        // The retail LegoRR section overrides default Lego* sound settings.
        if let enabled = (config.value("LegoRR", "SoundOn") ??
                          config.valueUnderGame(["SoundOn"]))?.uppercased(),
           ["FALSE", "NO", "OFF"].contains(enabled) {
            return "sound disabled in Lego.cfg"
        }

        // SFX_RegisterName(SFX_AmbientMusicLoop) hashes the full enum
        // identifier, including "SFX_" (src/openlrr/game/audio/SFX.h).
        // Lego.cfg's Samples key must therefore include that prefix.
        let candidates: [SoundSampleCatalog.Sample]
        do {
            candidates = try SoundSampleCatalog(config: config)
                .samples(named: "SFX_AmbientMusicLoop")
        } catch {
            return "menu audio config: \(error)"
        }
        let directory = selectedWadURL.deletingLastPathComponent()
        let manager = FileManager.default

        for sample in candidates {
            let path = sample.wavPath.replacingOccurrences(of: "\\", with: "/")
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            // Never follow absolute or parent-relative paths from an asset file.
            guard !components.isEmpty,
                  components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":") }) else {
                continue
            }

            var bytes: Data?
            if resources.exists(path) {
                bytes = try? resources.data(at: path, maximumBytes: 50_000_000)
            }

            if bytes == nil {
                // The original installer also keeps streamed WAVs as ordinary
                // files in Data/, rather than in LegoRR0/1.wad.
                // If the WAD itself was placed inside Data/, the original
                // streamed sounds are relative to its parent install folder.
                for url in [directory.appendingPathComponent("Data").appendingPathComponent(path),
                            directory.appendingPathComponent(path),
                            directory.deletingLastPathComponent().appendingPathComponent("Data").appendingPathComponent(path)] {
                    guard let attributes = try? manager.attributesOfItem(atPath: url.path),
                          let length = attributes[.size] as? NSNumber,
                          (44...50_000_000).contains(length.intValue),
                          let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                        continue
                    }
                    bytes = data
                    break
                }
            }

            guard let bytes, let audio = try? AVAudioPlayer(data: bytes) else {
                continue
            }
            audio.numberOfLoops = -1
            // DirectSound attenuation uses 100ths of a decibel.
            audio.volume = Float(pow(10.0, Double(sample.volume) / 2000.0))
            audio.prepareToPlay()
            if audio.play() {
                player = audio
                return "original menu ambience playing"
            }
        }
        let firstPath = candidates.first?.wavPath.replacingOccurrences(of: "\\\\", with: "/") ?? "unknown"
        return "menu ambience unavailable: \(firstPath)"
    }
}
#endif
