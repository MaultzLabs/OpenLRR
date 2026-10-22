// Offline, on-Mac slicing of the game-window H.264 master video.
// Uses built-in AVFoundation, not ffmpeg, and never uploads anything.
// Produces short MP4s only; all original master video remains private.
import AVFoundation
import CoreMedia
import Foundation

enum ExportFailure: Error { case invalid, asset, export, excess }

@main struct GameVideoSplitter {
    static func main() async {
        guard CommandLine.arguments.count == 4,
              let chunkSeconds = Double(CommandLine.arguments[3]),
              chunkSeconds >= 30, chunkSeconds <= 600 else {
            fputs("usage: video_split MASTER.mp4 OUTPUT_DIRECTORY CHUNK_SECONDS\n", stderr)
            exit(2)
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let destination = URL(fileURLWithPath: CommandLine.arguments[2],
                              isDirectory: true)
        do {
            guard source.pathExtension.lowercased() == "mp4",
                  FileManager.default.fileExists(atPath: source.path) else {
                throw ExportFailure.invalid
            }
            try FileManager.default.createDirectory(
                at: destination, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let asset = AVURLAsset(url: source)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration.isFinite, duration > 0 else {
                throw ExportFailure.asset
            }
            // 150 MiB provides upload headroom under the 512 MB per-file cap.
            // Passthrough copies encoded samples; no quality-losing re-encode.
            let maxBytes: Int64 = 150 * 1024 * 1024
            let originalVideo = try await asset.loadTracks(withMediaType: .video)
            let originalAudio = try await asset.loadTracks(withMediaType: .audio)
            guard !originalVideo.isEmpty else { throw ExportFailure.asset }
            let sourceHasAudio = !originalAudio.isEmpty
            var index = 0
            var descriptors: [[String: Any]] = []

            func outputClip(start: Double, length: Double) async throws {
                // The first chunk uses a 5-minute target; overly large
                // chunks split further until below 180 MiB (or 30 seconds).
                let indexCandidate = index + 1
                let name = String(format: "part-%04d.mp4", indexCandidate)
                let url = destination.appendingPathComponent(name)
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    throw ExportFailure.invalid
                }
                guard let exporter = AVAssetExportSession(
                    asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                    throw ExportFailure.export
                }
                exporter.outputURL = url
                exporter.outputFileType = .mp4
                exporter.shouldOptimizeForNetworkUse = true
                exporter.timeRange = CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: length, preferredTimescale: 600))
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    exporter.exportAsynchronously { continuation.resume() }
                }
                guard exporter.status == .completed else {
                    try? FileManager.default.removeItem(at: url)
                    throw ExportFailure.export
                }
                let fileInfo = try FileManager.default.attributesOfItem(atPath: url.path)
                let count = (fileInfo[.size] as? NSNumber)?.int64Value ?? 0
                guard count > 4096 else {
                    try? FileManager.default.removeItem(at: url)
                    throw ExportFailure.export
                }
                // A successful export status alone does not prove a playable
                // video or that the original audio track survived the split.
                let clipAsset = AVURLAsset(url: url)
                let outputDurationTime = try await clipAsset.load(.duration)
                let outputDuration = CMTimeGetSeconds(outputDurationTime)
                let outputVideo = try await clipAsset.loadTracks(withMediaType: .video)
                let outputAudio = try await clipAsset.loadTracks(withMediaType: .audio)
                guard outputDuration.isFinite, outputDuration > 0,
                      !outputVideo.isEmpty,
                      (!sourceHasAudio || !outputAudio.isEmpty) else {
                    try? FileManager.default.removeItem(at: url)
                    throw ExportFailure.export
                }
                if count > maxBytes {
                    try FileManager.default.removeItem(at: url)
                    guard length > 30 else {
                        // At least preserve a truncated warning; a 30-sec
                        // upload may require local re-encode, do not pretend.
                        throw ExportFailure.excess
                    }
                    let left = length / 2
                    try await outputClip(start: start, length: left)
                    try await outputClip(start: start + left, length: length - left)
                    return
                }
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: url.path)
                index += 1
                descriptors.append([
                    "file": name, "start_s": start,
                    "duration_s": length, "decoded_duration_s": outputDuration,
                    "audio_track_present": !outputAudio.isEmpty,
                    "video_track_present": true, "bytes": count
                ])
            }
            var start = 0.0
            while start < duration {
                let length = min(chunkSeconds, duration - start)
                try await outputClip(start: start, length: length)
                start += length
            }
            let report: [String: Any] = [
                "schema": "openlrr-window-video-clips-v1",
                "source": "local_game_window_master",
                "total_duration_s": duration,
                "clip_count": descriptors.count,
                "max_bytes_per_clip": maxBytes,
                "source_audio_track_present": sourceHasAudio,
                "time_basis": "requested_source_time_range_start; exported samples may align to keyframes",
                "clips": descriptors
            ]
            guard let bytes = try? JSONSerialization.data(
                withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) else {
                throw ExportFailure.export
            }
            let manifest = destination.appendingPathComponent("clips.json")
            try bytes.write(to: manifest, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: manifest.path)
            print("Generated \(descriptors.count) verified MP4 clips under 150 MiB each.")
        } catch {
            fputs("Video splitting incomplete. Original master is untouched.\n", stderr)
            exit(3)
        }
    }
}
