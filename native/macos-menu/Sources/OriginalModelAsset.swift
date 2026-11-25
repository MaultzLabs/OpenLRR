import Foundation

/// OpenLRR's gameplay world has horizontal X/Y and an up vector (0, 0, -1)
/// (Camera.cpp::Camera_Update). Original LWOB/LWS nodes share this basis.
/// Native SceneKit terrain has horizontal X/Z and up (0, 1, 0).
/// Rotate original *model roots*, not individual LWS keys, about X by +90°:
/// (original x, y, z) -> (native x, -z, y). The rotation preserves handedness,
/// hierarchy, authored pivots and original camera-null animation.
enum OriginalModelCoordinateBasis {
    static let sceneKitRootPitchRadians = Double.pi / 2
}

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

    /// Creature_FindNull(Creature_GetCarryNull) looks up the AE's
    /// CarryNullName at frame 0 through Container_FormatPartName, not an
    /// invented hand offset. No authored null means no visible carried mesh.
    var carryNullPartName: String? {
        guard let name = definition.valueUnderGame(["CarryNullName"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return name + "_00"
    }

    /// Creature_Load reads AE CameraFlipDir via Config_GetBoolValue;
    /// Creature_IsCameraFlipDir recognizes only BOOL3_TRUE. The original
    /// Util_GetBoolFromString accepts YES/TRUE/ON (case-insensitive).
    var cameraFlipDirection: Bool {
        guard cameraNullPartName(frame: 0) != nil,
              let text = definition.valueUnderGame(["CameraFlipDir"]) else { return false }
        return ["YES", "TRUE", "ON"].contains(text.uppercased())
    }

    /// Creature_Load / Creature_GetCameraNull locate the original frame with
    /// Container_FormatPartName's LWS "name_%02d" convention. The executable
    /// stores at most CREATURE_MAXCAMERAS (4) entries; never guess a frame.
    func cameraNullPartName(frame: Int) -> String? {
        guard let name = definition.valueUnderGame(["CameraNullName"])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let countText = definition.valueUnderGame(["CameraNullFrames"]),
              let count = Int(countText), (1...4).contains(count),
              (0..<count).contains(frame) else { return nil }
        return name + "_" + String(format: "%02d", frame)
    }
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
        return try load(path: entry.path, sharedObjects: activities.sharedObjects,
                        looping: entry.looping, resources: resources)
    }

    /// Container_Load(LWS) is also used directly by original rockfall effects.
    static func load(path: String, sharedObjects: String?, looping: Bool,
                     resources: GameResources) throws -> Self {
        guard OriginalModelActivities.safe(path), path.lowercased().hasSuffix(".lws") else {
            throw OriginalModelActivities.AssetError.invalid("unsafe LWS path \(path)")
        }
        let scene = try LightWaveScene(data: resources.data(at: path, maximumBytes: 4_000_000))
        let components: [OriginalLightWaveMeshAsset?] = try scene.objects.map { object in
            guard let filename = object.filename else { return nil }
            let candidates = LightWaveScene.candidatePaths(reference: filename, scenePath: path,
                                                            sharedObjects: sharedObjects)
            guard let component = candidates.first(where: { resources.exists($0) }) else {
                throw OriginalModelActivities.AssetError.invalid(
                    "missing component \(filename) in \(path); searched \(candidates.joined(separator: ", "))")
            }
            return try OriginalLightWaveMeshAsset.load(path: component, resources: resources)
        }
        guard components.contains(where: { $0 != nil }) else {
            throw OriginalModelActivities.AssetError.invalid("empty scene \(path)")
        }
        return Self(path: path, scene: scene, components: components, looping: looping)
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

/// Effects.cpp::Effect_Load_RockFallStylesAll reads ordered
/// <TumbleNullName>,<3Sides>,<OutsideCorner>,<VTunnel> style entries.
/// Game.cpp::Lego_PTL_RockFall chooses the first two by adjacent floor count.
/// No guessed filenames or generated falling rocks.
struct OriginalRockFallAsset {
    let clip: OriginalLightWaveClipAsset
    let tumbleIndices: [Int]

    static func typeIndex(adjacentFloors: Int) -> Int {
        adjacentFloors <= 1 ? 0 : 1
    }

    static func load(config: LegoConfig, level: String, typeIndex: Int,
                     resources: GameResources) throws -> Self {
        let styles = Array(config.settingsUnderGame(["RockFallStyles"]).prefix(4))
        let chosen = config.valueUnderGame(["Levels", level, "RockFallStyle"])
        let style = chosen.flatMap { name in
            styles.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        } ?? (chosen == nil ? styles.first : nil)
        guard let style, (0...2).contains(typeIndex) else {
            throw OriginalModelActivities.AssetError.invalid("missing configured rockfall style")
        }
        let fields = style.value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard fields.indices.contains(typeIndex + 1), !fields[0].isEmpty else {
            throw OriginalModelActivities.AssetError.invalid("missing rockfall type \(typeIndex)")
        }
        let base = fields[typeIndex + 1].replacingOccurrences(of: "\\", with: "/")
        guard OriginalModelActivities.safe(base) else {
            throw OriginalModelActivities.AssetError.invalid("unsafe rockfall scene \(base)")
        }
        let path = base + (base.lowercased().hasSuffix(".lws") ? "" : ".lws")
        let clip = try OriginalLightWaveClipAsset.load(path: path,
            sharedObjects: config.valueUnderGame(["Main", "SharedObjects"]),
            looping: false, resources: resources)
        // Lws_Parse keeps the raw AddNullObject label; Lws_CreateFrames
        // appends _00, _01 ... for repeated names. Effect_GetTumbleNull_RockFall
        // assigns the first unused instance, capped at its 32-bit mask.
        let indices = clip.scene.objects.indices.filter {
            clip.scene.objects[$0].nullName?.caseInsensitiveCompare(fields[0]) == .orderedSame
        }
        return Self(clip: clip, tumbleIndices: Array(indices.prefix(32)))
    }

    // Effect_UpdateAll passes elapsedWorld (standard 25Hz frame units) to
    // Container_MoveAnimation. Convert that to the shared clip's FPS clock.
    var duration: Double { Double(max(1, clip.scene.lastFrame)) / 25.0 }
    func rendererElapsed(worldSeconds: Double) -> Double {
        min(duration, max(0, worldSeconds)) * 25.0 / clip.scene.framesPerSecond
    }
}
