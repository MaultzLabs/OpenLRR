import Foundation

/// Container_Load(ACT): <directory>/<basename>.ae, then an Activities entry
/// names a section containing FILE/LWSFILE/LOOPING. Used by Raiders AND buildings.
struct OriginalModelActivities {
    enum AssetError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let reason): return "Original model unavailable: \(reason)" }
        }
    }

    struct Activity {
        let path: String
        let looping: Bool
    }

    let directory: String
    let definition: LegoConfig
    let sharedObjects: String?
    let scale: Double

    init(directory: String, definition: LegoConfig, sharedObjects: String? = nil) throws {
        var normalized = directory.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard Self.safe(normalized) else { throw AssetError.invalid("model directory \(directory)") }
        self.directory = normalized
        self.definition = definition
        self.sharedObjects = sharedObjects
        if let raw = definition.valueUnderGame(["Scale"]) {
            guard let value = Double(raw), value.isFinite, Float(value).isFinite else {
                throw AssetError.invalid("invalid AE Scale \(raw)")
            }
            // Containers.cpp:611–613 applies nonzero Scale; zero/missing leaves identity.
            self.scale = value == 0 ? 1 : value
        } else { self.scale = 1 }
    }

    static func safe(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 1024 && !path.contains(":") &&
        !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
        path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func load(config: LegoConfig, resources: GameResources) throws -> Self {
        guard let directory = config.valueUnderGame(["MiniFigureTypes", "Pilot"]) else {
            throw AssetError.invalid("missing MiniFigureTypes::Pilot")
        }
        return try load(directory: directory, resources: resources,
                        sharedObjects: config.valueUnderGame(["Main", "SharedObjects"]))
    }

    static func load(directory: String, resources: GameResources, sharedObjects: String?) throws -> Self {
        var normalized = directory.replacingOccurrences(of: "\\", with: "/")
        while normalized.hasSuffix("/") { normalized.removeLast() }
        guard Self.safe(normalized), let name = normalized.split(separator: "/").last else {
            throw AssetError.invalid("model directory \(directory)")
        }
        let path = "\(normalized)/\(name).ae"
        let data = try resources.data(at: path, maximumBytes: 1_000_000)
        return try Self(directory: normalized, definition: LegoConfig(data: data), sharedObjects: sharedObjects)
    }

    func activity(_ name: String) throws -> Activity {
        guard let section = definition.valueUnderGame(["Activities", name]) ??
                definition.valueUnderGame(["Activities", "!" + name]),
              let file = definition.valueUnderGame([section, "FILE"]) else {
            throw AssetError.invalid("missing \(name) FILE in \(directory)")
        }
        guard let lws = definition.valueUnderGame([section, "LWSFILE"]),
              ["TRUE", "YES", "ON"].contains(lws.uppercased()) else {
            throw AssetError.invalid("\(directory) \(name) is not a supported LWS activity (LWSFILE TRUE required)")
        }
        let relative = file.replacingOccurrences(of: "\\", with: "/")
        guard Self.safe(relative) else { throw AssetError.invalid("unsafe activity FILE \(file)") }
        // Utils.cpp:216–225 / Containers.cpp:581–583: only FALSE/NO/OFF
        // disable looping. Missing/unknown settings (including 0) default true.
        let looping = !["FALSE", "NO", "OFF"].contains(
            (definition.valueUnderGame([section, "LOOPING"]) ?? "").uppercased())
        return Activity(path: directory + "/" + relative +
            (relative.lowercased().hasSuffix(".lws") ? "" : ".lws"), looping: looping)
    }

    func scenePath(activity: String) throws -> String { try self.activity(activity).path }
}

/// Portable original bytes decoded once, then used by the common SceneKit
/// renderer. Missing/corrupt components fail explicitly, never fabricate meshes.
struct OriginalLightWaveMeshAsset {
    let path: String
    let mesh: LightWaveObject
    let uvMap: LightWaveUVMap?

    static func load(path: String, resources: GameResources) throws -> Self {
        guard OriginalModelActivities.safe(path), path.lowercased().hasSuffix(".lwo") else {
            throw OriginalModelActivities.AssetError.invalid("unsafe LWOB path \(path)")
        }
        let mesh = try LightWaveObject(data: resources.data(at: path, maximumBytes: 20_000_000))
        guard !mesh.triangles.isEmpty else {
            throw OriginalModelActivities.AssetError.invalid("empty mesh \(path)")
        }
        let uvPath = String(path.dropLast(4)) + ".uv"
        let uv = resources.exists(uvPath) ? try LightWaveUVMap(
            data: resources.data(at: uvPath, maximumBytes: 16_000_000), mesh: mesh) : nil
        return Self(path: path, mesh: mesh, uvMap: uv)
    }
}

struct OriginalLightWaveClipAsset {
    let path: String
    let scene: LightWaveScene
    let components: [OriginalLightWaveMeshAsset?]
    let looping: Bool

    static func load(activities: OriginalModelActivities, activity: String,
                     resources: GameResources) throws -> Self {
        let entry = try activities.activity(activity)
        let scene = try LightWaveScene(data: resources.data(at: entry.path, maximumBytes: 4_000_000))
        let components: [OriginalLightWaveMeshAsset?] = try scene.objects.map { object in
            guard let filename = object.filename else { return nil }
            let candidates = LightWaveScene.candidatePaths(reference: filename, scenePath: entry.path,
                                                            sharedObjects: activities.sharedObjects)
            guard let path = candidates.first(where: { resources.exists($0) }) else {
                throw OriginalModelActivities.AssetError.invalid(
                    "missing component \(filename) in \(entry.path); searched \(candidates.joined(separator: ", "))")
            }
            return try OriginalLightWaveMeshAsset.load(path: path, resources: resources)
        }
        guard components.contains(where: { $0 != nil }) else {
            throw OriginalModelActivities.AssetError.invalid("empty scene \(entry.path)")
        }
        return Self(path: entry.path, scene: scene, components: components, looping: entry.looping)
    }

    // Preserve the native clip clock (declared LWS FPS) for now; retail's
    // game-tick / object-stat animation rates need their own gameplay port.
    // Lws_SetTime (Lws.cpp:476–486) wraps at LastFrame, not frameCount, and
    // clamps non-looping clips. FirstFrame is not an animation start offset.
    var duration: TimeInterval { Double(max(1, scene.lastFrame)) / scene.framesPerSecond }
    func frame(elapsed: TimeInterval) -> Double {
        guard scene.lastFrame > 0 else { return 0 }
        let time = max(0, elapsed) * scene.framesPerSecond
        return looping ? time.truncatingRemainder(dividingBy: Double(scene.lastFrame)) :
            min(time, Double(scene.lastFrame))
    }
}
