import Foundation

/// Maps the original Lego.cfg `Samples` entries to their real .wav resources.
/// Based on SFX_LoadSampleProperty in game/audio/SFX.cpp and Sound3D_Load in
/// engine/audio/3DSound.cpp. This only resolves user-owned archive resources;
/// it does not play sound or synthesize replacement effects.
struct SoundSampleCatalog {
    enum SampleError: Error, CustomStringConvertible {
        case missing(String)
        case invalid(String)
        case unavailableStream(String)

        var description: String {
            switch self {
            case .missing(let id): return "No configured sound effect: \(id)"
            case .invalid(let reason): return "Invalid original sound definition: \(reason)"
            case .unavailableStream(let path): return "Streaming sound requires file-backed playback: \(path)"
            }
        }
    }

    struct Sample {
        let wavPath: String
        let simultaneous: Bool
        let streamed: Bool
        let volume: Int // Original DirectSound attenuation range: -10000...0.
    }

    private let config: LegoConfig

    init(config: LegoConfig) { self.config = config }

    /// Original '!' keys are reduced-sample variants. By default we include
    /// them, as the normal game does without the -reducesamples switch.
    func samples(named identifier: String, includeReduced: Bool = true) throws -> [Sample] {
        guard !identifier.isEmpty, identifier.utf8.count <= 256 else {
            throw SampleError.invalid("invalid sound identifier")
        }
        let raw = config.valueUnderGame(["Samples", identifier]) ??
                  (includeReduced ? config.valueUnderGame(["Samples", "!" + identifier]) : nil)
        guard let raw else { throw SampleError.missing(identifier) }
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 100 else {
            throw SampleError.invalid("sound group has too many samples")
        }

        var result: [Sample] = []
        result.reserveCapacity(parts.count)
        // Original SFX_LoadSampleProperty declares stream outside its group
        // loop: once @ appears, later entries are also treated as streamed.
        var stream = false
        for (index, part) in parts.enumerated() {
            var entry = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            var simultaneous = false
            var volume = 0
            if entry.hasPrefix("*") {
                simultaneous = true
                entry.removeFirst()
            }
            if entry.hasPrefix("#") {
                entry.removeFirst()
                guard let close = entry.firstIndex(of: "#"), close != entry.startIndex,
                      let parsed = Int(entry[..<close]) else {
                    throw SampleError.invalid("unterminated or invalid volume in sample \(index)")
                }
                // The original Sound3D_Load resets invalid volume to 0.
                volume = (-10_000...0).contains(parsed) ? parsed : 0
                entry = String(entry[entry.index(after: close)...])
            }
            if entry.hasPrefix("@") {
                stream = true
                entry.removeFirst()
            }
            guard !entry.isEmpty, entry.utf8.count <= 1024,
                  !entry.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw SampleError.invalid("missing or invalid filename in sample \(index)")
            }
            guard !(stream && simultaneous) else {
                throw SampleError.invalid("streamed sample cannot also be simultaneous")
            }
            // Sound3D_Load appends .wav to the configured basename verbatim.
            result.append(Sample(wavPath: entry + ".wav", simultaneous: simultaneous,
                                 streamed: stream, volume: volume))
        }
        return result
    }

    /// Loads a non-streaming sample directly from the selected original WADs.
    /// No sample is written to disk, and streamed files are not emulated.
    func pcm(named identifier: String, variant: Int = 0,
             resources: GameResources, includeReduced: Bool = true) throws -> WavePCM {
        let group = try samples(named: identifier, includeReduced: includeReduced)
        guard group.indices.contains(variant) else {
            throw SampleError.invalid("sample variant is outside its configured group")
        }
        let selected = group[variant]
        guard !selected.streamed else {
            throw SampleError.unavailableStream(selected.wavPath)
        }
        return try WavePCM(data: resources.data(at: selected.wavPath, maximumBytes: 50_000_000))
    }
}
