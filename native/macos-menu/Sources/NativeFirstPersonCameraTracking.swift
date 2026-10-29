import Foundation

/// Keep first-person viewing attached to the active original ACT/LWS camera
/// null even when movement input is blocked by a drilling activity.
/// Creature_GetCameraNull resolves the null; native code only follows its
/// transform. No camera offset or replacement geometry is invented here.
enum NativeFirstPersonCameraTracking {
    struct Position: Equatable {
        let x: Double
        let y: Double
        let z: Double

        var isFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
    }

    /// Malformed animation transforms must not poison the SceneKit camera.
    /// A missing/nonfinite original null uses the existing provisional eye.
    static func resolvedPosition(original: Position?, fallback: Position) -> Position {
        guard let original, original.isFinite else { return fallback }
        return original
    }
}

#if os(macOS)
import SceneKit

extension NativeFirstPersonCameraTracking {
    static func synchronize(camera: SCNNode, animatedAnchor: SCNNode?,
                            fallback: SCNVector3, heading: Double) {
        let original = animatedAnchor.map {
            let position = $0.presentation.worldPosition
            return Position(x: Double(position.x), y: Double(position.y), z: Double(position.z))
        }
        let position = resolvedPosition(
            original: original,
            fallback: Position(x: Double(fallback.x), y: Double(fallback.y), z: Double(fallback.z)))
        camera.position = SCNVector3(Float(position.x), Float(position.y), Float(position.z))
        // Retail frame orientation and CameraFlipDir still require validation.
        // Until then keep the existing controller heading convention.
        camera.eulerAngles = SCNVector3(0, Float(heading + .pi), 0)
    }
}
#endif
