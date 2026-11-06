import Foundation

// Retain the original call-site/test API while sharing ACT loading with buildings.
typealias OriginalRaiderActivities = OriginalModelActivities

#if os(macOS)
import SceneKit

final class OriginalRaiderModel {
    let root = SCNNode()
    private let standing: OriginalLightWaveRenderer.Clip
    private let walking: OriginalLightWaveRenderer.Clip
    private let drilling: OriginalLightWaveRenderer.Clip?
    private let cameraPartNames: [String]
    let cameraFlipDirection: Bool
    var cameraFrameCount: Int { cameraPartNames.count }
    private(set) var selectedCameraFrame = 0
    private var firstPersonEnabled = false

    private struct GeometrySet {
        let clip: OriginalLightWaveRenderer.Clip
        let original: [SCNGeometry?]
        // One MeshLOD set per authored CameraNullFrames entry; every set
        // includes all parts so changing frames restores the previous set.
        let firstPerson: [[SCNGeometry?]]
        let targeted: [[Bool]]
    }
    private var geometrySets: [GeometrySet] = []
    private(set) var firstPersonMeshDiagnostic: String?
    private var isDrilling = false
    private var moving = false
    private var epoch = ProcessInfo.processInfo.systemUptime

    /// Activity selection must agree with both the animated camera attachment
    /// and which original LWS geometry is actually visible. Some original
    /// Stand/Route/Drill clips do not contain the parts named by FPPoly.
    private var activeClip: OriginalLightWaveRenderer.Clip {
        isDrilling ? (drilling ?? standing) : (moving ? walking : standing)
    }

    /// True only if the CURRENT activity has an authentic first-person mesh
    /// in the selected camera set. Checking every loaded clip previously kept
    /// the full body visible when the active clip lacked its FPPoly parts.
    var showingFirstPersonMeshes: Bool {
        guard firstPersonEnabled,
              let set = geometrySets.first(where: { $0.clip === activeClip }),
              set.firstPerson.indices.contains(selectedCameraFrame) else { return false }
        return set.firstPerson[selectedCameraFrame].contains { $0 != nil }
    }

    init(activities: OriginalRaiderActivities, resources: GameResources, blockSize: Double,
         sharedTextures: String? = nil) throws {
        guard blockSize.isFinite, blockSize > 0 else {
            throw OriginalModelActivities.AssetError.invalid("BlockSize")
        }
        func clip(_ activity: String) throws -> OriginalLightWaveRenderer.Clip {
            OriginalLightWaveRenderer.Clip(asset: try OriginalLightWaveClipAsset.load(
                activities: activities, activity: activity, resources: resources),
                resources: resources, sharedTextures: sharedTextures)
        }
        cameraPartNames = (0..<4).compactMap { activities.cameraNullPartName(frame: $0) }
        cameraFlipDirection = activities.cameraFlipDirection
        standing = try clip("Activity_Stand")
        walking = try clip("Activity_Route")
        drilling = try? clip("Activity_Drill")
        root.addChildNode(standing.root)
        root.addChildNode(walking.root)
        walking.root.isHidden = true
        if let drilling { root.addChildNode(drilling.root); drilling.root.isHidden = true }
        let scale = Float(activities.scale / blockSize)
        root.scale = SCNVector3(scale, scale, scale)
        // Retail LightWave space is -Z up; SceneKit cave space is +Y up.
        // Apply once above every Stand/Route/Drill clip and camera-null frame.
        root.eulerAngles.x = CGFloat(OriginalModelCoordinateBasis.sceneKitRootPitchRadians)
        // Match Creature_Load and MeshLOD_SwapTarget: each original CameraN
        // has its own authored replacements; never reuse Camera0 for all
        // camera nulls or generate replacement meshes.
        do {
            let lod = try OriginalFirstPersonMeshLOD.load(activities: activities, resources: resources)
            if lod.hasFirstPersonMeshes {
                for clip in [standing, walking] + (drilling.map { [$0] } ?? []) {
                    let replacements = lod.frames.map { cameraSet in
                        clip.parts.map { part -> (Bool, SCNGeometry?) in
                            guard let name = part.name,
                                  let replacement = cameraSet.first(where: {
                                      OriginalFirstPersonMeshLOD.matches(partName: $0.partName,
                                                                         lwsName: name)
                                  }) else { return (false, nil) }
                            return (true, replacement.mesh.map {
                                OriginalLightWaveRenderer.geometry(asset: $0, resources: resources,
                                                                  sharedTextures: sharedTextures)
                            })
                        }
                    }
                    geometrySets.append(GeometrySet(
                        clip: clip, original: clip.parts.map(\.geometry),
                        firstPerson: replacements.map { $0.map { $0.1 } },
                        targeted: replacements.map { $0.map { $0.0 } }))
                }
                if !geometrySets.contains(where: {
                    $0.firstPerson.contains(where: { $0.contains(where: { $0 != nil }) })
                }) {
                    firstPersonMeshDiagnostic = "Original FPPoly parts did not match the Stand/Route/Drill LWS objects"
                    geometrySets.removeAll()
                }
            }
        } catch {
            // Unsupported/missing retail FPPoly never breaks the regular Raider.
            firstPersonMeshDiagnostic = String(describing: error)
        }
        // All model roots are ground-based. Diagnostic capsule offsets belong
        // to the view's proxy child, not to the original asset hierarchy.
        update(time: epoch)
    }

    /// Change the original camera-null frame and its corresponding FPPoly
    /// MeshLOD set together. The caller decides how to expose this control;
    /// native diagnostic keys are not claimed to match retail input mappings.
    @discardableResult
    func selectFirstPersonCameraFrame(_ frame: Int) -> Bool {
        guard cameraPartNames.indices.contains(frame) else { return false }
        selectedCameraFrame = frame
        if firstPersonEnabled { applyFirstPersonMeshes() }
        return true
    }

    private func applyFirstPersonMeshes() {
        for set in geometrySets {
            for index in set.clip.parts.indices {
                if set.targeted[selectedCameraFrame][index] {
                    let geometry = set.firstPerson[selectedCameraFrame][index]
                    set.clip.parts[index].geometry = geometry
                } else {
                    // An untargeted part may have been replaced by the
                    // previous camera set; always restore its original mesh.
                    set.clip.parts[index].geometry = set.original[index]
                }
            }
        }
    }

    /// Retain true first-person mode even if the requested frame has no
    /// matching FPPoly. Its normal body must then be hidden by the view.
    @discardableResult
    func setFirstPerson(_ enabled: Bool) -> Bool {
        firstPersonEnabled = enabled
        if enabled && !geometrySets.isEmpty {
            applyFirstPersonMeshes()
        } else {
            for set in geometrySets {
                for index in set.clip.parts.indices {
                    set.clip.parts[index].geometry = set.original[index]
                }
            }
        }
        return showingFirstPersonMeshes
    }

    func setMoving(_ value: Bool) {
        guard moving != value || isDrilling else { return }
        isDrilling = false
        drilling?.root.isHidden = true
        moving = value
        epoch = ProcessInfo.processInfo.systemUptime
        standing.root.isHidden = moving
        walking.root.isHidden = !moving
    }

    /// Return the actual named, animated LWS camera null for this activity.
    /// The view uses a provisional eye height only when that retail frame
    /// cannot be resolved. Camera heading/flip still need parity validation.
    func firstPersonCameraAnchor() -> SCNNode? {
        guard cameraPartNames.indices.contains(selectedCameraFrame) else { return nil }
        let name = cameraPartNames[selectedCameraFrame]
        return activeClip.parts.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
    }

    func beginDrilling() -> TimeInterval? {
        guard let drilling else { return nil }
        isDrilling = true; moving = false
        epoch = ProcessInfo.processInfo.systemUptime
        standing.root.isHidden = true; walking.root.isHidden = true
        drilling.root.isHidden = false
        return drilling.asset.duration
    }

    /// Preserve the current animation frame across an initial objective pause.
    func rebaseTime(afterPausedFor duration: TimeInterval) {
        guard duration.isFinite, duration >= 0 else { return }
        epoch += duration
    }

    func update(time: TimeInterval) {
        activeClip.update(elapsed: max(0, time - epoch))
    }
}
#endif
