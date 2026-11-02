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

    /// Camera_Update accepts a full forward vector and fixes camera up at
    /// original (0, 0, -1). Keep the authored LWS null's vertical component,
    /// rather than flattening every drill/head pose to the controller's yaw.
    struct Direction: Equatable {
        let x: Double
        let y: Double
        let z: Double
        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    private static func unit(_ direction: Direction?) -> Direction? {
        guard let direction, direction.isFinite else { return nil }
        let length = hypot(hypot(direction.x, direction.y), direction.z)
        guard length.isFinite && length > 1e-9 else { return nil }
        return Direction(x: direction.x / length, y: direction.y / length,
                         z: direction.z / length)
    }

    /// The native controller retains a documented provisional yaw fallback
    /// when the original frame is absent, degenerate, or vertical enough to
    /// make the original fixed-up orientation indeterminate.
    static func resolvedDirection(original: Direction?, fallbackHeading: Double) -> Direction {
        if let direction = unit(original),
           hypot(direction.x, direction.z) > 0.001 { return direction }
        let yaw = fallbackHeading.isFinite ? fallbackHeading : 0
        return Direction(x: sin(yaw), y: 0, z: cos(yaw))
    }

    static func requiresDirectionSnap(current: Direction?, target: Direction) -> Bool {
        guard let a = unit(current), let b = unit(target) else { return false }
        return a.x * b.x + a.y * b.y + a.z * b.z < 0
    }

    /// Source Camera_Update weights the old **3-D** direction by
    /// 4 / elapsedAbs, with a reversal snap and a 0.99999 dot threshold.
    /// elapsedAbs is in 25-Hz ticks, while this helper receives seconds.
    static func smoothedDirection(current: Direction?, target: Direction,
                                  elapsedSeconds: Double) -> Direction {
        guard let target = unit(target) else {
            return unit(current) ?? Direction(x: 0, y: 0, z: 1)
        }
        guard let current = unit(current) else { return target }
        guard elapsedSeconds.isFinite && elapsedSeconds > 0 else { return current }
        let dot = current.x * target.x + current.y * target.y + current.z * target.z
        if dot < 0 { return target }
        if dot >= 0.99999 { return current }
        let ticks = min(elapsedSeconds, 1) * 25
        let blend = ticks / (4 + ticks)
        return unit(Direction(x: current.x * (1 - blend) + target.x * blend,
                              y: current.y * (1 - blend) + target.y * blend,
                              z: current.z * (1 - blend) + target.z * blend)) ?? target
    }
}

#if os(macOS)
import SceneKit

extension NativeFirstPersonCameraTracking {
    /// SceneKit cameras face local -Z; original containers return +Z forward.
    /// The preceding retail LWSC model-root basis converts that direction to
    /// native world space. Read live model transforms, not hidden presentation
    /// nodes, while original Stand/Route/Drill clips advance.
    static func synchronize(camera: SCNNode, animatedAnchor: SCNNode?,
                            fallback: SCNVector3, heading: Double, cameraFlipDir: Bool = false,
                            elapsedSeconds: Double, blockSize: Double, firstFrame: Bool) {
        let original = animatedAnchor.map {
            let p = $0.worldPosition
            return Position(x: Double(p.x), y: Double(p.y), z: Double(p.z))
        }
        let target = resolvedPosition(original: original,
            fallback: Position(x: Double(fallback.x), y: Double(fallback.y), z: Double(fallback.z)))

        let rawFacing: Direction? = animatedAnchor.map { anchor in
            let vector = anchor.convertVector(SCNVector3(0, 0, 1), to: nil)
            let sign = cameraFlipDir ? -1.0 : 1.0
            return Direction(x: Double(vector.x) * sign,
                             y: Double(vector.y) * sign,
                             z: Double(vector.z) * sign)
        }
        let direction = resolvedDirection(original: rawFacing, fallbackHeading: heading)
        let oldFacing: Direction? = firstFrame ? nil : {
            let vector = camera.convertVector(SCNVector3(0, 0, -1), to: nil)
            return Direction(x: Double(vector.x), y: Double(vector.y), z: Double(vector.z))
        }()
        let reverse = requiresDirectionSnap(current: oldFacing, target: direction)
        let previous = firstFrame || reverse ? nil : Position(
            x: Double(camera.position.x), y: Double(camera.position.y), z: Double(camera.position.z))
        let next = smoothedPosition(current: previous, target: target,
                                    elapsedSeconds: elapsedSeconds, blockSize: blockSize)
        camera.position = SCNVector3(Float(next.x), Float(next.y), Float(next.z))
        let facing = smoothedDirection(current: oldFacing, target: direction,
                                       elapsedSeconds: elapsedSeconds)
        // Camera_Update passes original up (0, 0, -1), converted to +Y.
        // Keep the original null's pitch and controller's safe fallback.
        camera.look(at: SCNVector3(Float(next.x + facing.x),
                                   Float(next.y + facing.y),
                                   Float(next.z + facing.z)),
                    up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }
}
#endif
