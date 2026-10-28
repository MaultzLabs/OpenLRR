import Foundation

/// Reads the classic LightWave Scene version 1 (LWSC 1) text files shipped
/// with the 1999 PC game. In particular, Menu::MenuWipe points to a genuine
/// animated LWS scene with Boulder*.lwo components.
///
/// Ref: LightWave pre-6 scene format (key records contain nine motion
/// channels on one line and frame/linear/TCB metadata on the next).
/// This is a bounded, read-only parser. Original assets never leave the WAD.
struct LightWaveScene {
    enum SceneError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let why): return "Invalid LightWave scene: \(why)" }
        }
    }

    struct MotionKey {
        let frame: Double
        /// x, y, z, heading, pitch, bank, scaleX, scaleY, scaleZ
        let channels: [Double]

        func channel(_ index: Int) -> Double { channels[index] }
    }

    struct Object {
        let filename: String?          // nil for a LightWave null/group object.
        let keys: [MotionKey]
        let pivot: [Double]
        let parentIndex: Int?          // 1-based index as encoded by LWSC 1.

        func channels(at frame: Double) -> [Double] {
            guard let first = keys.first else { return [0,0,0,0,0,0,1,1,1] }
            if frame <= first.frame { return first.channels }
            guard let last = keys.last else { return first.channels }
            if frame >= last.frame { return last.channels }
            for n in 1..<keys.count where frame <= keys[n].frame {
                let a = keys[n-1], b = keys[n]
                let divisor = b.frame - a.frame
                guard divisor > 0 else { return b.channels }
                let t = (frame - a.frame) / divisor
                return zip(a.channels, b.channels).map { pair in
                    pair.0 + (pair.1 - pair.0) * t
                }
            }
            return last.channels
        }
    }

    let firstFrame: Int
    let lastFrame: Int
    let framesPerSecond: Double
    let objects: [Object]

    var frameCount: Int { lastFrame - firstFrame + 1 }
    var duration: TimeInterval { Double(frameCount) / framesPerSecond }

    init(data: Data) throws {
        guard data.count <= 4_000_000,
              let source = String(data: data, encoding: .utf8) ??
                           String(data: data, encoding: .isoLatin1) else {
            throw SceneError.invalid("missing or oversized text scene")
        }
        let lines = source.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("#") }
        guard lines.count >= 2 && lines.count <= 40_000,
              lines[0] == "LWSC", lines[1] == "1" else {
            throw SceneError.invalid("expected LWSC version 1")
        }
        var firstFrame = 0, lastFrame = 0
        var fps = 25.0
        struct Pending {
            var name: String?
            var keys: [MotionKey] = []
            var parent: Int?
            var pivot = [0.0, 0.0, 0.0]
        }
        var pending: [Pending] = []
        var cursor = 2

        func arguments(_ line: String) -> String {
            guard let end = line.firstIndex(where: { $0 == " " || $0 == "\t" })
                else { return "" }
            return String(line[line.index(after: end)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        while cursor < lines.count {
            let line = lines[cursor]
            let key = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .first.map(String.init) ?? ""
            switch key {
            case "FirstFrame":
                if let value = Int(arguments(line)) { firstFrame = value }
            case "LastFrame":
                if let value = Int(arguments(line)) { lastFrame = value }
            case "FramesPerSecond":
                if let value = Double(arguments(line)), value.isFinite { fps = value }
            case "LoadObject", "LoadObjectLayer", "AddNullObject":
                guard pending.count < 512 else {
                    throw SceneError.invalid("scene contains too many objects")
                }
                let raw: String
                if key == "LoadObjectLayer" {
                    let fields = arguments(line).split(maxSplits: 1, whereSeparator: {
                        $0 == " " || $0 == "\t"
                    })
                    raw = fields.count == 2 ? String(fields[1]) : ""
                } else {
                    raw = arguments(line)
                }
                // The original scene may refer to a filename with spaces.
                // Preserve the raw path; only the bounded game resource
                // resolver decides whether it is safe to load.
                let name = raw.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                pending.append(Pending(name: key == "AddNullObject" ? nil : name))
            case "ParentObject":
                if !pending.isEmpty {
                    let value = Int(arguments(line))
                    pending[pending.count - 1].parent = value
                }
            case "PivotPoint":
                let values = arguments(line).split(whereSeparator: \.isWhitespace).compactMap { Double($0) }
                guard !pending.isEmpty, values.count == 3, values.allSatisfy(\.isFinite) else {
                    throw SceneError.invalid("invalid pivot")
                }
                pending[pending.count - 1].pivot = values
            case "ObjectMotion":
                guard !pending.isEmpty, cursor + 2 < lines.count,
                      Int(lines[cursor+1]) == 9,
                      let keyCount = Int(lines[cursor+2]),
                      (0...10_000).contains(keyCount),
                      keyCount <= (lines.count-cursor-3)/2 else {
                    throw SceneError.invalid("invalid original ObjectMotion header")
                }
                cursor += 3
                var keys: [MotionKey] = []
                keys.reserveCapacity(keyCount)
                for _ in 0..<keyCount {
                    let channels = lines[cursor].split(whereSeparator: \.isWhitespace)
                        .compactMap { Double($0) }
                    let metadata = lines[cursor+1].split(whereSeparator: \.isWhitespace)
                        .compactMap { Double($0) }
                    guard channels.count == 9,
                          metadata.count >= 1,
                          channels.allSatisfy(\.isFinite),
                          metadata[0].isFinite,
                          abs(metadata[0]) < 100_000,
                          (keys.last?.frame ?? -Double.greatestFiniteMagnitude) <= metadata[0] else {
                        throw SceneError.invalid("invalid original motion keyframe")
                    }
                    keys.append(MotionKey(frame: metadata[0], channels: channels))
                    cursor += 2
                }
                pending[pending.count - 1].keys = keys
                continue
            default: break
            }
            cursor += 1
        }
        guard firstFrame >= 0, lastFrame >= firstFrame,
              lastFrame-firstFrame <= 10_000,
              fps > 0 && fps <= 240 else {
            throw SceneError.invalid("invalid animation frame range or frame rate")
        }
        for index in pending.indices {
            var seen = Set<Int>(), current = index
            while let parent = pending[current].parent, parent != 0 {
                guard (1...pending.count).contains(parent), seen.insert(current).inserted else {
                    throw SceneError.invalid("invalid or cyclic parent hierarchy")
                }
                current = parent - 1
            }
        }
        self.firstFrame = firstFrame
        self.lastFrame = lastFrame
        self.framesPerSecond = fps
        self.objects = pending.map { Object(filename: $0.name, keys: $0.keys,
                                             pivot: $0.pivot, parentIndex: $0.parent) }
    }

    /// Lws_Parse discards the author's directories; Lws_LoadMesh tries the
    /// scene directory before Main::SharedObjects (Lws.cpp:112–117,793–817).
    static func candidatePaths(reference: String, scenePath: String,
                               sharedObjects: String? = nil) -> [String] {
        LightWaveResourcePaths.candidates(reference: reference, assetPath: scenePath,
            sharedDirectory: sharedObjects, requiredExtension: "lwo")
    }
}

/// Ordered archive-relative lookups shared by LWS components and LWOB textures.
/// Author-machine paths identify a basename, never a host file or search root.
/// Existence/read checks remain in GameResources, preserving WAD priority and
/// failing closed when a higher-priority archive entry cannot be read.
enum LightWaveResourcePaths {
    static func candidates(reference: String, assetPath: String,
                           sharedDirectory: String?, requiredExtension: String) -> [String] {
        let raw = reference.replacingOccurrences(of: "\\", with: "/")
        let asset = assetPath.replacingOccurrences(of: "\\", with: "/")
        guard reference.utf8.count <= 8192, !hasControlCharacters(reference),
              let filename = raw.split(separator: "/", omittingEmptySubsequences: false)
                .last.map(String.init),
              filename.utf8.count <= 256, safePath(filename),
              filename.lowercased().hasSuffix("." + requiredExtension),
              safePath(asset) else { return [] }

        let directory = asset.split(separator: "/").dropLast().joined(separator: "/")
        let local = directory.isEmpty ? filename : directory + "/" + filename
        guard safePath(local) else { return [] }
        var result = [local]
        if var shared = sharedDirectory?.replacingOccurrences(of: "\\", with: "/"),
           shared.utf8.count <= 1024 {
            // Configured game directories may end in a separator, but must
            // never be converted from absolute/parent paths to relative ones.
            while shared.hasSuffix("/") { shared.removeLast() }
            if safePath(shared) {
                let path = shared + "/" + filename
                if safePath(path), !result.contains(where: { $0.lowercased() == path.lowercased() }) {
                    result.append(path)
                }
            }
        }
        return result
    }

    private static func hasControlCharacters(_ path: String) -> Bool {
        path.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    private static func safePath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 1024 && !path.contains(":") &&
        !hasControlCharacters(path) &&
        path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
