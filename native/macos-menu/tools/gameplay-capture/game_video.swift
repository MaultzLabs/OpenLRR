// Rock Raiders WINDOW-ONLY continuous H.264 video recorder, macOS 15+.
// Source/format must come from precisely identified CGWindowID + owner PID.
// The SCContentFilter is desktopIndependentWindow -- NEVER a desktop capture.
// No app injection, no microphone, no keyboard text, no automatic upload.
// Audio capture is app-scoped by ScreenCaptureKit; only selected Wine app audio,
// including its other windows, should be included when the OS associates it.
import AppKit
import Foundation
import CoreGraphics
import CoreMedia
import ScreenCaptureKit
import AVFoundation

struct GameTarget {
    let id: Int
    let pid: Int
    let output: URL
    let fps: Int
    let maxSeconds: Int
}

func allowedGame(title: String, owner: String) -> Bool {
    let t = title.lowercased(), o = owner.lowercased()
    let gameTitle = ["rock raiders", "legorr", "openlrr"].contains(where: t.contains)
    let gameOwner = ["wine", "wineskin", "whisky", "crossover", "sikarugir",
                     "rock raiders", "legorr", "openlrr"].contains(where: o.contains)
    return gameTitle && gameOwner
}

func exactWindowStillExists(_ target: GameTarget) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                               kCGNullWindowID) as? [[String: Any]] else {
        return false
    }
    for item in list {
        guard (item[kCGWindowNumber as String] as? NSNumber)?.intValue == target.id,
              (item[kCGWindowOwnerPID as String] as? NSNumber)?.intValue == target.pid,
              (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              let bounds = item[kCGWindowBounds as String] as? [String: Any],
              let w = (bounds["Width"] as? NSNumber)?.doubleValue,
              let h = (bounds["Height"] as? NSNumber)?.doubleValue,
              w >= 320, w <= 8192, h >= 200, h <= 8192 else {
            continue
        }
        return allowedGame(title: item[kCGWindowName as String] as? String ?? "",
                           owner: item[kCGWindowOwnerName as String] as? String ?? "")
    }
    return false
}

func emit(_ name: String, extra: [String: Any] = [:]) {
    var record: [String: Any] = [
        "source": "video", "event": name,
        "unix_s": Date().timeIntervalSince1970,
        "monotonic_s": ProcessInfo.processInfo.systemUptime,
    ]
    for (key, value) in extra { record[key] = value }
    guard JSONSerialization.isValidJSONObject(record),
          let encoded = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
          let json = String(data: encoded, encoding: .utf8) else { return }
    print(json)
    fflush(stdout)
}

final class StopControl {
    private let lock = NSLock()
    private var stopRequested = false
    func stop() { lock.lock(); stopRequested = true; lock.unlock() }
    var requested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }
}

@available(macOS 15.0, *)
final class Recorder: NSObject, SCStreamDelegate, SCRecordingOutputDelegate {
    private let lock = NSLock()
    private var didFinish = false
    private var didFail = false

    func recordingOutputDidStartRecording(_ output: SCRecordingOutput) {
        emit("recording_started")
    }
    func recordingOutputDidFinishRecording(_ output: SCRecordingOutput) {
        lock.lock(); didFinish = true; lock.unlock()
        emit("recording_finalized")
    }
    func recordingOutput(_ output: SCRecordingOutput, didFailWithError error: Error) {
        lock.lock(); didFail = true; lock.unlock()
        emit("recording_failed")
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); didFail = true; lock.unlock()
        emit("stream_failed")
    }
    private var status: (finished: Bool, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (didFinish, didFail)
    }

    func run(_ target: GameTarget) async -> Int {
        guard exactWindowStillExists(target) else {
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
            }), exactWindowStillExists(target) else {
                emit("target_missing")
                return 2
            }

            // Captures only the approved window, never any display or desktop.
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = max(320, min(3840, Int(window.frame.width * 2)))
            config.height = max(200, min(2160, Int(window.frame.height * 2)))
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(target.fps))
            config.queueDepth = 5
            config.showsCursor = true
            config.capturesAudio = true  // Single-window filter limits audio by owning app.
            config.excludesCurrentProcessAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            let file = SCRecordingOutputConfiguration()
            file.outputURL = target.output
            file.outputFileType = .mp4
            file.videoCodecType = .h264

            let stream = SCStream(filter: filter, configuration: config, delegate: self)
            let output = SCRecordingOutput(configuration: file, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()
            emit("capture_started", extra: [
                "window_id": target.id, "fps_target": target.fps,
                "scope": "single_game_window", "audio_requested": true,
                "audio_scope": "owning_application", "microphone": false
            ])

            let stop = StopControl()
            DispatchQueue.global(qos: .utility).async {
                // Parent sends STOP then newline. EOF also stops.
                while let command = readLine() {
                    if command == "STOP" { break }
                }
                stop.stop()
            }
            let deadline = Date().addingTimeInterval(Double(target.maxSeconds))
            var stopReason = "parent_stopped"
            while !stop.requested {
                if !exactWindowStillExists(target) {
                    stopReason = "game_window_closed"
                    break
                }
                if status.failed {
                    stopReason = "stream_error"
                    break
                }
                if Date() >= deadline {
                    stopReason = "time_limit"
                    break
                }
                try await Task.sleep(nanoseconds: 250_000_000)
            }
            emit("capture_stopping", extra: ["reason": stopReason])
            try await stream.stopCapture()
            let finalizeDeadline = Date().addingTimeInterval(20)
            while !status.finished && !status.failed && Date() < finalizeDeadline {
                try await Task.sleep(nanoseconds: 150_000_000)
            }
            guard status.finished && !status.failed else {
                emit("finalization_unverified")
                return 3
            }
            let attributes = try FileManager.default.attributesOfItem(
                atPath: target.output.path)
            guard let bytes = attributes[.size] as? NSNumber,
                  bytes.int64Value > 4096 else {
                emit("video_too_small")
                return 4
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: target.output.path)
            // Presence of an audio track must be checked, not inferred from
            // capturesAudio=true. Wine may emit sound from a different app.
            let recordedAsset = AVURLAsset(url: target.output)
            let audioTracks = try await recordedAsset.loadTracks(withMediaType: .audio)
            emit("video_complete", extra: [
                "audio_track_present": !audioTracks.isEmpty,
                "audio_scope": "owning_application",
                "bytes": bytes.int64Value,
                "duration_s": CMTimeGetSeconds(output.recordedDuration),
                "stop_reason": stopReason
            ])
            return 0
        } catch {
            emit("capture_error")
            return 5
        }
    }
}

guard CommandLine.arguments.count == 6,
      let windowID = Int(CommandLine.arguments[1]),
      let ownerPID = Int(CommandLine.arguments[2]),
      windowID > 0, ownerPID > 0,
      let fps = Int(CommandLine.arguments[4]),
      let maxSeconds = Int(CommandLine.arguments[5]),
      fps >= 1, fps <= 60,
      maxSeconds >= 1, maxSeconds <= 4 * 60 * 60 else {
    fputs("usage: game_video WINDOW_ID OWNER_PID OUTPUT.mp4 FPS MAX_SECONDS\n", stderr)
    exit(2)
}
let path = CommandLine.arguments[3]
guard path.hasSuffix(".mp4"), !FileManager.default.fileExists(atPath: path) else {
    fputs("refusing unsafe video output path\n", stderr)
    exit(2)
}
let target = GameTarget(id: windowID, pid: ownerPID,
                        output: URL(fileURLWithPath: path),
                        fps: fps, maxSeconds: maxSeconds)
if #available(macOS 15.0, *) {
    let recorder = Recorder()
    Task {
        let code = await recorder.run(target)
        exit(Int32(code))
    }
    RunLoop.main.run()
} else {
    fputs("ScreenCaptureKit MP4 recording requires macOS 15 or later\n", stderr)
    exit(2)
}
