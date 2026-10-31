import Foundation

/// Follow the active original ACT/LWS camera null with the original engine's
/// first-person positional damping; no synthetic camera geometry is created.
enum NativeFirstPersonCameraTracking {
    struct Position: Equatable {
        let x: Double
        let y: Double
        let z: Double
        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    static func resolvedPosition(original: Position?, fallback: Position) -> Position {
        guard let original, original.isFinite else { return fallback }
        return original
    }

    /// Camera.cpp::Camera_Update uses (target + previous*(4/elapsedAbs)) /
    /// (1 + 4/elapsedAbs), snaps beyond 100 world units, and suppresses moves
    /// at or below 0.01 world unit. SceneKit positions are measured in tiles,
    /// so use the original BlockSize to compare world-unit displacements.
    static func smoothedPosition(current: Position?, target: Position,
                                 elapsedSeconds: Double, blockSize: Double) -> Position {
        guard target.isFinite else { return current?.isFinite == true ? current! : target }
        guard let current, current.isFinite else { return target }
        guard elapsedSeconds.isFinite, elapsedSeconds > 0,
              blockSize.isFinite, blockSize > 0 else { return current }
        let distance = hypot(hypot(target.x - current.x, target.y - current.y),
                             target.z - current.z) * blockSize
        if !distance.isFinite || distance > 100 { return target }
        if distance <= 0.01 { return current }
        // Original engine elapsedAbs counts 25-Hz game ticks.
        let ticks = min(elapsedSeconds, 1) * 25
        let blend = ticks / (4 + ticks)
        return Position(x: current.x + (target.x - current.x) * blend,
                        y: current.y + (target.y - current.y) * blend,
                        z: current.z + (target.z - current.z) * blend)
    }

    /// Camera_Update smooths first-person facing as a normalized direction,
    /// not by averaging yaw angles. The source snaps on a reversed facing dot
    /// (< 0), suppresses sub-0.00001 directional changes and blends with
    /// previous direction * (4 / elapsedAbs). Heading is the native X/Z
    /// horizontal-plane fallback until the original CameraFlipDir and
    /// animated-null orientation are independently verified.
    static func smoothedHeading(current: Double?, target: Double,
                                elapsedSeconds: Double) -> Double {
        guard target.isFinite else { return current?.isFinite == true ? current! : 0 }
        let targetNormalized = atan2(sin(target), cos(target))
        guard let current, current.isFinite else { return targetNormalized }
        guard elapsedSeconds.isFinite, elapsedSeconds > 0 else { return current }
        let dot = cos(targetNormalized - current)
        if dot < 0 { return targetNormalized }
        if dot >= 0.99999 { return current }
        let ticks = min(elapsedSeconds, 1) * 25
        // Algebraically the original weighted vector, without 4/ticks
        // overflowing for extremely small positive frame intervals.
        let blend = ticks / (4 + ticks)
        return atan2((1 - blend) * sin(current) + blend * sin(targetNormalized),
                     (1 - blend) * cos(current) + blend * cos(targetNormalized))
    }

    static func requiresDirectionSnap(current: Double?, target: Double) -> Bool {
        guard let current, current.isFinite, target.isFinite else { return false }
        return cos(target - current) < 0
    }
}

#if os(macOS)
import SceneKit

extension NativeFirstPersonCameraTracking {
    static func synchronize(camera: SCNNode, animatedAnchor: SCNNode?,
                            fallback: SCNVector3, heading: Double, elapsedSeconds: Double,
                            blockSize: Double, firstFrame: Bool) {
        let original = animatedAnchor.map {
            // The Raider is hidden in first person; presentation.worldPosition
            // may be stale while Clip.update changes the LWS model transform.
            let position = $0.worldPosition
            return Position(x: Double(position.x), y: Double(position.y), z: Double(position.z))
        }
        let target = resolvedPosition(original: original,
            fallback: Position(x: Double(fallback.x), y: Double(fallback.y), z: Double(fallback.z)))
        let oldHeading = firstFrame ? nil : Double(camera.eulerAngles.y) - Double.pi
        let suddenReverse = requiresDirectionSnap(current: oldHeading, target: heading)
        let previous = firstFrame || suddenReverse ? nil : Position(
            x: Double(camera.position.x), y: Double(camera.position.y), z: Double(camera.position.z))
        let position = smoothedPosition(current: previous, target: target,
                                        elapsedSeconds: elapsedSeconds, blockSize: blockSize)
        camera.position = SCNVector3(Float(position.x), Float(position.y), Float(position.z))
        let facing = smoothedHeading(current: oldHeading, target: heading,
                                     elapsedSeconds: elapsedSeconds)
        camera.eulerAngles = SCNVector3(0, Float(facing + .pi), 0)
    }
}
#endif
