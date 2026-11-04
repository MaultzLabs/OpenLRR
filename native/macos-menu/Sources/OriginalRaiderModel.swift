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
    private let cameraPartName: String?
    let cameraFlipDirection: Bool
    private struct GeometrySet {
        let clip: OriginalLightWaveRenderer.Clip
        let original: [SCNGeometry?]
        let firstPerson: [SCNGeometry?]
    }
    private var geometrySets: [GeometrySet] = []
    private(set) var showingFirstPersonMeshes = false
    private(set) var firstPersonMeshDiagnostic: String?
    private var isDrilling = false
    private var moving = false
    private var epoch = ProcessInfo.processInfo.systemUptime

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
        cameraPartName = activities.cameraNullPartName(frame: 0)
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
        // MeshLOD_SwapTarget swaps rendered part geometry, not the animated
        // transform hierarchy. Preserve the original LWS camera nulls and
        // the normal Stand/Route/Drill meshes for immediate restoration.
        do {
            let lod = try OriginalFirstPersonMeshLOD.load(activities: activities, resources: resources)
            if let first = lod.frames.first, lod.hasFirstPersonMeshes {
                for clip in [standing, walking] + (drilling.map { [$0] } ?? []) {
                    let replacements: [SCNGeometry?] = clip.parts.map { part in
                        guard let name = part.name,
                              let replacement = first.first(where: {
                                  OriginalFirstPersonMeshLOD.matches(partName: $0.partName,
                                                                     lwsName: name)
                              }) else { return nil }
                        return replacement.mesh.map {
                            OriginalLightWaveRenderer.geometry(asset: $0, resources: resources,
                                                              sharedTextures: sharedTextures)
                        }
                    }
                    geometrySets.append(GeometrySet(clip: clip, original: clip.parts.map(\.geometry),
                                                    firstPerson: replacements))
                }
                if !geometrySets.contains(where: { $0.firstPerson.contains(where: { $0 != nil }) }) {
                    firstPersonMeshDiagnostic = "Original FPPoly parts did not match the Stand/Route/Drill LWS objects"
                    geometrySets.removeAll()
                }
            }
        } catch {
            // An unsupported/missing FPPoly never breaks the regular original
            // Raider model. First person stays camera-only and diagnostic.
            firstPersonMeshDiagnostic = String(describing: error)
        }
        // All model roots are ground-based. Diagnostic capsule offsets belong
        // to the view's proxy child, not to the original asset hierarchy.
        update(time: epoch)
    }

    /// The first retail camera set is currently selected by native F mode.
    /// Only genuine FPPoly geometry appears; no substitute tool or artwork.
    @discardableResult
    func setFirstPerson(_ enabled: Bool) -> Bool {
        guard !enabled || !geometrySets.isEmpty else { return false }
        for set in geometrySets {
            let geometries = enabled ? set.firstPerson : set.original
            for (node, geometry) in zip(set.clip.parts, geometries) {
                node.geometry = geometry
            }
        }
        showingFirstPersonMeshes = enabled
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
        guard let name = cameraPartName else { return nil }
        let clip = isDrilling ? (drilling ?? standing) : moving ? walking : standing
        return clip.parts.first { $0.name?.caseInsensitiveCompare(name) == .orderedSame }
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
        let clip = isDrilling ? (drilling ?? standing) : moving ? walking : standing
        clip.update(elapsed: max(0, time - epoch))
    }
}
#endif
