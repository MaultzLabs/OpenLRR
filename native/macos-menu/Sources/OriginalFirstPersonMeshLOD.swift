import Foundation

/// Reads the retail AE FPPoly::CameraN mesh-LOD replacement tables. The
/// original Creature_Load passes CameraNullFrames to LegoObject_LoadMeshLOD,
/// then Creature_SwapPolyFP swaps matching LWS part geometries for one camera
/// set. Keep camera sets separate; never synthesize first-person hands/tools.
struct OriginalFirstPersonMeshLOD {
    struct Replacement {
        let partName: String
        /// NULL_OBJECT deliberately removes the corresponding original part.
        let mesh: OriginalLightWaveMeshAsset?
    }

    let frames: [[Replacement]]
    var hasFirstPersonMeshes: Bool {
        frames.first?.contains(where: { $0.mesh != nil }) ?? false
    }

    static func load(activities: OriginalModelActivities,
                     resources: GameResources) throws -> Self {
        // No valid original camera frames means no supported FPPoly attachment.
        guard activities.cameraNullPartName(frame: 0) != nil else {
            return Self(frames: [])
        }
        var sets: [[Replacement]] = []
        for camera in 0..<4 {
            guard activities.cameraNullPartName(frame: camera) != nil else { break }
            let settings = activities.definition.settingsUnderGame(["FPPoly", "Camera\(camera)"])
            guard settings.count <= 128 else {
                throw OriginalModelActivities.AssetError.invalid("FPPoly Camera\(camera) has too many parts")
            }
            var seen = Set<String>()
            var parts: [Replacement] = []
            for (part, raw) in settings {
                guard !part.isEmpty, part.utf8.count <= 128,
                      !part.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                      seen.insert(part.lowercased()).inserted else {
                    throw OriginalModelActivities.AssetError.invalid("invalid FPPoly part in Camera\(camera)")
                }
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if ["NULL", "NULL_OBJECT"].contains(name.uppercased()) {
                    parts.append(Replacement(partName: part, mesh: nil))
                    continue
                }
                let relative = name.replacingOccurrences(of: "\\", with: "/")
                // MeshLOD_Create loads from the model directory. Do not allow
                // absolute/parent paths or substitute from unrelated assets.
                guard OriginalModelActivities.safe(relative),
                      !relative.lowercased().hasSuffix(".x"),
                      !relative.hasSuffix("/") else {
                    throw OriginalModelActivities.AssetError.invalid("unsafe FPPoly mesh \(name)")
                }
                let file = relative.lowercased().hasSuffix(".lwo") ? relative : relative + ".lwo"
                let path = activities.directory + "/" + file
                guard OriginalModelActivities.safe(path) else {
                    throw OriginalModelActivities.AssetError.invalid("unsafe FPPoly path \(name)")
                }
                parts.append(Replacement(partName: part,
                    mesh: try OriginalLightWaveMeshAsset.load(path: path, resources: resources)))
            }
            sets.append(parts)
        }
        return Self(frames: sets)
    }

    /// LWS LoadObject names may include the original LightWave author folder
    /// and .lwo extension; the MeshLOD table names the corresponding part.
    /// Compare only the complete basename (no substring/partial matching).
    static func matches(partName: String, lwsName: String) -> Bool {
        func basename(_ text: String) -> String {
            let last = text.replacingOccurrences(of: "\\", with: "/")
                .split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? ""
            return last.lowercased().hasSuffix(".lwo") ? String(last.dropLast(4)).lowercased() : last.lowercased()
        }
        let part = basename(partName), node = basename(lwsName)
        return !part.isEmpty && part == node
    }
}
