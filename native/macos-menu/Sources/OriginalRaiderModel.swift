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
        standing = try clip("Activity_Stand")
        walking = try clip("Activity_Route")
        drilling = try? clip("Activity_Drill")
        root.addChildNode(standing.root)
        root.addChildNode(walking.root)
        walking.root.isHidden = true
        if let drilling { root.addChildNode(drilling.root); drilling.root.isHidden = true }
        let scale = Float(activities.scale / blockSize)
        root.scale = SCNVector3(scale, scale, scale)
        // All model roots are ground-based. Diagnostic capsule offsets belong
        // to the view's proxy child, not to the original asset hierarchy.
        update(time: epoch)
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
