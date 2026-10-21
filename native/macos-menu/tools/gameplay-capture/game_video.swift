// Window-only continuous Rock Raiders VIDEO + owning app audio, macOS 15+.
// Record a NEW, finalized 90-second MP4 while the window is still running.
// Previous clips survive even if Wine closes its window without warning.
// Never capture displays/desktops, unrelated apps, microphone, or key text.
import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

struct GameTarget {
    let id: Int
    let pid: Int
    let directory: URL
    let fps: Int
    let maxSeconds: Int
    let segmentSeconds: Int
}

func allowedGame(title: String, owner: String) -> Bool {
    let t = title.lowercased(), o = owner.lowercased()
    return ["rock raiders", "legorr", "openlrr"].contains(where: t.contains) &&
        ["wine", "wineskin", "whisky", "crossover", "sikarugir",
         "rock raiders", "legorr", "openlrr"].contains(where: o.contains)
}

func sameGameWindow(_ target: GameTarget) -> Bool {
    guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                  kCGNullWindowID) as? [[String: Any]] else {
        return false
    }
    for item in windows {
        guard (item[kCGWindowNumber as String] as? NSNumber)?.intValue == target.id,
              (item[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == target.pid,
              (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let w = (bounds["Width"] as? NSNumber)?.doubleValue,
              let h = (bounds["Height"] as? NSNumber)?.doubleValue,
              w >= 320, w <= 8192, h >= 200, h <= 8192 else { continue }
        return allowedGame(title: item[kCGWindowName as String] as? String ?? "",
                           owner: item[kCGWindowOwnerName as String] as? String ?? "")
    }
    return false
}

func emit(_ event: String, extra: [String: Any] = [:]) {
    var fields: [String: Any] = [
        "source": "video", "event": event,
        "unix_s": Date().timeIntervalSince1970,
        "monotonic_s": ProcessInfo.processInfo.systemUptime
    ]
    for (name, value) in extra { fields[name] = value }
    guard JSONSerialization.isValidJSONObject(fields),
          let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    print(json)
    fflush(stdout)
}

final class StopControl {
    private let lock = NSLock()
    private var stopped = false
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
    }
    var requested: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopped
    }
}

@available(macOS 15.0, *)
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private let lock = NSLock()
    private var finished = false
    private var outputFailed = false
    private var streamStopped = false

    private var snapshot: (finished: Bool, outputFailed: Bool, streamStopped: Bool) {
        lock.lock(); defer { lock.unlock() }
        return (finished, outputFailed, streamStopped)
    }
    private func resetOutputStatus() {
        lock.lock()
        finished = false
        outputFailed = false
        lock.unlock()
    }

    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        emit("recording_started")
    }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        lock.lock(); finished = true; lock.unlock()
        emit("recording_finalized")
    }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        lock.lock(); outputFailed = true; lock.unlock()
        emit("recording_failed", extra: ["error_code": (error as NSError).code])
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); streamStopped = true; lock.unlock()
        emit("stream_failed", extra: ["error_code": (error as NSError).code])
    }

    // Finalize an output while the stream is still ACTIVE. Apple documents
    // removeRecordingOutput as recording-only shutdown, independent from
    // stopCapture. Previous finalized files are never overwritten.
    private func finalize(_ output: SCRecordingOutput, stream: SCStream,
                          target: GameTarget, part: Int,
                          startOffset: Double) async -> Bool {
        do {
            try stream.removeRecordingOutput(output)
        } catch {
            emit("segment_finalize_failed", extra: [
                "part": part, "stage": "remove_output",
                "error_code": (error as NSError).code
            ])
            return false
        }
        let limit = Date().addingTimeInterval(20)
        while !snapshot.finished && !snapshot.outputFailed && Date() < limit {
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard snapshot.finished && !snapshot.outputFailed else {
            emit("segment_finalize_failed", extra: ["part": part, "stage": "finish_timeout"])
            return false
        }

        let name = String(format: "part-%04d.mp4", part)
        let url = target.directory.appendingPathComponent(name)
        do {
            let meta = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let bytes = meta[.size] as? NSNumber, bytes.int64Value > 4096 else {
                emit("segment_finalize_failed", extra: ["part": part, "stage": "file_too_small"])
                return false
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
            let asset = AVURLAsset(url: url)
            let durationTime = try await asset.load(.duration)
            let duration = CMTimeGetSeconds(durationTime)
            guard duration.isFinite && duration > 0 else {
                emit("segment_finalize_failed", extra: ["part": part, "stage": "invalid_duration"])
                return false
            }
            let audio = try? await asset.loadTracks(withMediaType: .audio)
            emit("segment_complete", extra: [
                "part": part, "start_offset_s": startOffset,
                "duration_s": duration, "bytes": bytes.int64Value,
                "audio_track_present": !(audio?.isEmpty ?? true)
            ])
            return true
        } catch {
            emit("segment_finalize_failed", extra: [
                "part": part, "stage": "verify_asset",
                "error_code": (error as NSError).code
            ])
            return false
        }
    }

    private func makeOutput(_ target: GameTarget, part: Int) -> SCRecordingOutput? {
        guard part >= 1 && part <= 9999 else { return nil }
        let name = String(format: "part-%04d.mp4", part)
        let url = target.directory.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: url.path) else { return nil }
        let config = SCRecordingOutputConfiguration()
        config.outputURL = url
        config.outputFileType = .mp4
        config.videoCodecType = .h264
        return SCRecordingOutput(configuration: config, delegate: self)
    }

    func run(_ target: GameTarget) async -> Int {
        guard sameGameWindow(target) else {
            emit("target_missing")
            return 2
        }
        do {
            let available = try await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: false)
            guard let window = available.windows.first(where: {
                Int($0.windowID) == target.id &&
                Int($0.owningApplication?.processID ?? -1) == target.pid &&
                allowedGame(title: $0.title ?? "",
                            owner: $0.owningApplication?.applicationName ?? "")
            }), sameGameWindow(target) else {
                emit("target_missing")
                return 2
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(320, min(3840, Int(window.frame.width * 2)))
            config.height = max(200, min(2160, Int(window.frame.height * 2)))
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(target.fps))
            config.queueDepth = 5
            config.showsCursor = true
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            var part = 1
            guard var output = makeOutput(target, part: part) else {
                emit("capture_error", extra: ["stage": "allocate_first_output"])
                return 3
            }
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            let start = Date()
            emit("capture_started", extra: [
                "window_id": target.id, "fps_target": target.fps,
                "scope": "single_game_window", "audio_requested": true,
                "audio_scope": "owning_application", "microphone": false,
                "segment_seconds": target.segmentSeconds
            ])

            let control = StopControl()
            DispatchQueue.global(qos: .utility).async {
                while let line = readLine() {
                    if line == "STOP" { break }
                }
                control.stop()
            }

            var offset = 0.0
            var successful = 0
            var stopReason = "parent_stopped"
            let deadline = start.addingTimeInterval(Double(target.maxSeconds))
            var segDeadline = start.addingTimeInterval(Double(target.segmentSeconds))
            while true {
                if control.requested {
                    stopReason = "parent_stopped"
                    break
                }
                if !sameGameWindow(target) {
                    stopReason = "game_window_closed"
                    break
                }
                if snapshot.streamStopped || snapshot.outputFailed {
                    stopReason = "stream_error"
                    break
                }
                if Date() >= deadline {
                    stopReason = "time_limit"
                    break
                }
                if Date() >= segDeadline {
                    // Before changing outputs, check the original target still
                    // exists; never fall back to desktop or another window.
                    if !sameGameWindow(target) {
                        stopReason = "game_window_closed"
                        break
                    }
                    if await finalize(output, stream: stream, target: target,
                                      part: part, startOffset: offset) {
                        successful += 1
                    } else {
                        stopReason = "segment_finalize_failed"
                        break
                    }
                    part += 1
                    guard let next = makeOutput(target, part: part) else {
                        stopReason = "segment_limit"
                        break
                    }
                    resetOutputStatus()
                    do {
                        try stream.addRecordingOutput(next)
                    } catch {
                        emit("capture_error", extra: [
                            "stage": "add_next_output",
                            "error_code": (error as NSError).code
                        ])
                        stopReason = "stream_error"
                        break
                    }
                    output = next
                    offset = Date().timeIntervalSince(start)
                    segDeadline = Date().addingTimeInterval(Double(target.segmentSeconds))
                }
                try await Task.sleep(nanoseconds: 180_000_000)
            }
            emit("capture_stopping", extra: [
                "reason": stopReason, "finished_segments": successful
            ])
            // Finalization here is best-effort because closing a Wine window
            // can already have stopped its SCStream. Earlier 90-second clips
            // stay finalized even when this final incomplete clip does not.
            if await finalize(output, stream: stream, target: target,
                              part: part, startOffset: offset) {
                successful += 1
            }
            do {
                try await stream.stopCapture()
            } catch {
                // Closing a Wine window may invalidate its stream BEFORE
                // we call stopCapture. Do not discard earlier valid MP4s.
                emit("stream_stop_error", extra: [
                    "error_code": (error as NSError).code
                ])
            }
            emit("capture_complete", extra: [
                "finished_segments": successful, "stop_reason": stopReason
            ])
            return successful > 0 ? 0 : 4
        } catch {
            emit("capture_error", extra: [
                "stage": "start_stream", "error_code": (error as NSError).code
            ])
            return 5
        }
    }
}

guard CommandLine.arguments.count == 7,
      let wid = Int(CommandLine.arguments[1]), wid > 0,
      let pid = Int(CommandLine.arguments[2]), pid > 0,
      let fps = Int(CommandLine.arguments[4]), (1...60).contains(fps),
      let duration = Int(CommandLine.arguments[5]), (1...14400).contains(duration),
      let segmentSeconds = Int(CommandLine.arguments[6]),
      (20...300).contains(segmentSeconds) else {
    fputs("usage: game_video WINDOW_ID OWNER_PID PRIVATE_CLIP_DIR FPS MAX_SECONDS SEGMENT_SECONDS\n", stderr)
    exit(2)
}
let directory = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
    fputs("output folder not found\n", stderr)
    exit(2)
}
let target = GameTarget(id: wid, pid: pid, directory: directory,
                        fps: fps, maxSeconds: duration, segmentSeconds: segmentSeconds)
if #available(macOS 15.0, *) {
    let recorder = Recorder()
    Task {
        let code = await recorder.run(target)
        exit(Int32(code))
    }
    RunLoop.main.run()
} else {
    fputs("requires macOS 15+\n", stderr)
    exit(2)
}
