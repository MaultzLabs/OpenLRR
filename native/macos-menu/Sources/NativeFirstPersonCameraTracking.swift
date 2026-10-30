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
        let previous = firstFrame ? nil : Position(
            x: Double(camera.position.x), y: Double(camera.position.y), z: Double(camera.position.z))
        let position = smoothedPosition(current: previous, target: target,
                                        elapsedSeconds: elapsedSeconds, blockSize: blockSize)
        camera.position = SCNVector3(Float(position.x), Float(position.y), Float(position.z))
        // Original camera orientation and CameraFlipDir remain unverified.
        camera.eulerAngles = SCNVector3(0, Float(heading + .pi), 0)
    }
}
#endif
