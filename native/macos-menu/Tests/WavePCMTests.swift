import Foundation

private func le16(_ n: UInt16) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8)]
}
private func le32(_ n: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
     UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
}
private func chunk(_ name: String, _ bytes: [UInt8]) -> [UInt8] {
    Array(name.utf8) + le32(UInt32(bytes.count)) + bytes + (bytes.count.isMultiple(of: 2) ? [] : [0])
}
private func wav(_ samples: [UInt8], channels: UInt16 = 1, rate: UInt32 = 8000,
                 bits: UInt16 = 8, formatTag: UInt16 = 1,
                 extra: [[UInt8]] = []) -> Data {
    let align = channels * (bits / 8)
    let fmt = le16(formatTag) + le16(channels) + le32(rate) +
              le32(rate * UInt32(align)) + le16(align) + le16(bits)
    let payload = Array("WAVE".utf8) + extra.flatMap { $0 } +
                  chunk("fmt ", fmt) + chunk("data", samples)
    return Data(Array("RIFF".utf8) + le32(UInt32(payload.count)) + payload)
}
private func expectReject(_ name: String, _ data: Data) {
    do { _ = try WavePCM(data: data); preconditionFailure("Accepted invalid WAV: \(name)") }
    catch is WavePCM.WaveError { print("Rejected \(name)") }
    catch { preconditionFailure("Unexpected error: \(error)") }
}
@main struct WavePCMTests {
    static func main() throws {
        let mono = try WavePCM(data: wav([0, 128, 255], extra: [chunk("JUNK", [1, 2, 3])]))
        precondition(mono.channels == 1 && mono.sampleRate == 8000 && mono.frameCount == 3)
        precondition(mono.bitsPerSample == 8 && mono.sample(frame: 0, channel: 0) == -1)
        precondition(mono.sample(frame: 1, channel: 0) == 0)
        precondition(mono.sample(frame: 2, channel: 0) == 127.0 / 128.0)
        precondition(mono.sample(frame: 3, channel: 0) == nil)
        precondition(mono.durationSeconds == 3.0 / 8000)
        let stereo = try WavePCM(data: wav([0, 128, 255, 127, 255, 255, 1, 0],
                                            channels: 2, rate: 22050, bits: 16))
        precondition(stereo.channels == 2 && stereo.frameCount == 2)
        precondition(stereo.sample(frame: 0, channel: 0) == -1)
        precondition(stereo.sample(frame: 0, channel: 1) == 32767.0 / 32768.0)
        precondition(stereo.sample(frame: 1, channel: 0) == -1.0 / 32768.0)
        precondition(stereo.sample(frame: 1, channel: 1) == 1.0 / 32768.0)
        expectReject("truncated WAV", Data(wav([0, 128]).dropLast(1)))
        expectReject("unsupported compressed format", wav([0, 128], formatTag: 6))
        expectReject("incomplete stereo sample frame", wav([0, 1, 2], channels: 2, bits: 16))
        expectReject("duplicate data chunks", {
            let original = wav([128])
            let payload = Array(original.dropFirst(8)) + chunk("data", [128])
            return Data(Array("RIFF".utf8) + le32(UInt32(payload.count)) + payload)
        }())
        expectReject("oversized RIFF chunk", {
            var corrupt = wav([128]); corrupt[4] = 255; corrupt[5] = 255
            return corrupt
        }())
        expectReject("missing padding", {
            let original = wav([128]); return Data(original.dropLast(1))
        }())
        print("PASS: PCM WAV 8/16-bit, mono/stereo, RIFF chunk padding, malformed input rejection")
    }
}
