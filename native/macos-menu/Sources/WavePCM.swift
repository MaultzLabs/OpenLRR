import Foundation

/// Read-only RIFF/WAVE PCM parser for original .wav sound effects.
/// OpenLRR's Sound3D_Load appends ".wav" to SFX filenames, and its streaming
/// path explicitly requires WAVE_FORMAT_PCM (src/openlrr/engine/audio/3DSound.cpp).
/// This validates the original bytes; it does not play audio or create assets.
struct WavePCM {
    enum WaveError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let reason): return "Invalid PCM WAV: \(reason)" }
        }
    }

    let channels: Int
    let sampleRate: Int
    let bitsPerSample: Int
    let frameCount: Int
    let pcmData: Data

    var durationSeconds: Double { Double(frameCount) / Double(sampleRate) }
    var bytesPerFrame: Int { channels * (bitsPerSample / 8) }

    init(data: Data) throws {
        guard (44...50_000_000).contains(data.count),
              data.prefix(4) == Data("RIFF".utf8),
              data[8..<12] == Data("WAVE".utf8) else {
            throw WaveError.invalid("missing RIFF/WAVE header or unreasonable size")
        }
        func u16(_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> Int {
            Int(data[offset]) | (Int(data[offset + 1]) << 8) |
            (Int(data[offset + 2]) << 16) | (Int(data[offset + 3]) << 24)
        }
        let riffSize = u32(4)
        guard riffSize >= 36, riffSize <= data.count - 8 else {
            throw WaveError.invalid("RIFF chunk exceeds file bounds")
        }
        let end = 8 + riffSize
        var cursor = 12
        var format: (channels: Int, rate: Int, bits: Int, alignment: Int)?
        var audioRange: Range<Int>?
        while cursor < end {
            guard end - cursor >= 8 else {
                throw WaveError.invalid("truncated RIFF chunk header")
            }
            let chunkType = Data(data[cursor..<(cursor + 4)])
            let chunkSize = u32(cursor + 4)
            let start = cursor + 8
            guard chunkSize <= end - start else {
                throw WaveError.invalid("RIFF chunk extends past declared size")
            }
            if chunkType == Data("fmt ".utf8) {
                guard format == nil, chunkSize >= 16 else {
                    throw WaveError.invalid("missing, duplicate or truncated fmt chunk")
                }
                let encoding = u16(start)
                let channels = u16(start + 2)
                let rate = u32(start + 4)
                let byteRate = u32(start + 8)
                let alignment = u16(start + 12)
                let bits = u16(start + 14)
                guard encoding == 1, (1...2).contains(channels),
                      (4_000...192_000).contains(rate), (bits == 8 || bits == 16),
                      alignment == channels * bits / 8,
                      byteRate == rate * alignment else {
                    throw WaveError.invalid("unsupported or inconsistent PCM format")
                }
                format = (channels, rate, bits, alignment)
            } else if chunkType == Data("data".utf8) {
                guard audioRange == nil, chunkSize > 0 else {
                    throw WaveError.invalid("missing or duplicate data chunk")
                }
                audioRange = start..<(start + chunkSize)
            }
            // RIFF chunks are word-aligned. Avoid reading a missing padding byte.
            let padding = chunkSize & 1
            guard padding <= end - start - chunkSize else {
                throw WaveError.invalid("missing RIFF alignment byte")
            }
            cursor = start + chunkSize + padding
        }
        guard let format, let audioRange,
              audioRange.count % format.alignment == 0 else {
            throw WaveError.invalid("missing PCM data or incomplete sample frame")
        }
        self.channels = format.channels
        self.sampleRate = format.rate
        self.bitsPerSample = format.bits
        self.frameCount = audioRange.count / format.alignment
        self.pcmData = Data(data[audioRange])
    }

    /// Decode one original PCM sample to [-1, 1). 8-bit PCM is unsigned;
    /// 16-bit PCM is little-endian signed, matching Windows WAVE_FORMAT_PCM.
    func sample(frame: Int, channel: Int) -> Double? {
        guard (0..<frameCount).contains(frame), (0..<channels).contains(channel) else {
            return nil
        }
        let offset = frame * bytesPerFrame + channel * bitsPerSample / 8
        if bitsPerSample == 8 {
            return (Double(pcmData[offset]) - 128.0) / 128.0
        }
        let word = UInt16(pcmData[offset]) | (UInt16(pcmData[offset + 1]) << 8)
        return Double(Int16(bitPattern: word)) / 32768.0
    }
}
