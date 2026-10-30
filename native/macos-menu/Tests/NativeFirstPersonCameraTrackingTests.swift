import Foundation
#if os(macOS)
import SceneKit
#endif

@main struct NativeFirstPersonCameraTrackingTests {
    typealias Tracking = NativeFirstPersonCameraTracking
    static func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.0001 }

    static func main() {
        let fallback = Tracking.Position(x: 0, y: 0.68, z: 0)
        let animated = Tracking.Position(x: -2, y: 1.5, z: 4)
        precondition(Tracking.resolvedPosition(original: animated, fallback: fallback) == animated)
        precondition(Tracking.resolvedPosition(original: nil, fallback: fallback) == fallback)
        for bad in [
            Tracking.Position(x: .nan, y: 1, z: 2),
            Tracking.Position(x: 1, y: .infinity, z: 2),
            Tracking.Position(x: 1, y: 2, z: -.infinity),
        ] {
            precondition(Tracking.resolvedPosition(original: bad, fallback: fallback) == fallback)
        }
        smoothingRegression()
        #if os(macOS)
        sceneKitFrameTracking()
        #endif
        print("PASS: original camera-null fallback, Camera_Update positional damping, teleport snap, animated drill tracking")
    }

    static func smoothingRegression() {
        let origin = Tracking.Position(x: 0, y: 0, z: 0)
        let target = Tracking.Position(x: 1, y: 2, z: -1)
        precondition(Tracking.smoothedPosition(current: nil, target: target,
                    elapsedSeconds: 0.04, blockSize: 40) == target)
        let next = Tracking.smoothedPosition(current: origin, target: target,
                                             elapsedSeconds: 0.04, blockSize: 40)
        precondition(near(next.x, 0.2) && near(next.y, 0.4) && near(next.z, -0.2),
                     "Original 4:1 weight at a 25-Hz tick")
        precondition(Tracking.smoothedPosition(current: origin, target: target,
                    elapsedSeconds: 0, blockSize: 40) == origin)
        precondition(Tracking.smoothedPosition(current: origin, target: target,
                    elapsedSeconds: .nan, blockSize: 40) == origin)
        precondition(Tracking.smoothedPosition(current: origin, target: target,
                    elapsedSeconds: 0.04, blockSize: 0) == origin)
        let far = Tracking.Position(x: 4, y: 0, z: 0)
        precondition(Tracking.smoothedPosition(current: origin, target: far,
                    elapsedSeconds: 0.04, blockSize: 40) == far,
                    "Teleport beyond 100 original world units must snap")
        let close = Tracking.Position(x: 0.00001, y: 0, z: 0)
        precondition(Tracking.smoothedPosition(current: origin, target: close,
                    elapsedSeconds: 0.04, blockSize: 40) == origin,
                    "Ignore sub-0.01-world-unit camera jitter")
        let bad = Tracking.Position(x: .infinity, y: 0, z: 0)
        precondition(Tracking.smoothedPosition(current: origin, target: bad,
                    elapsedSeconds: 0.04, blockSize: 40) == origin)
    }

    #if os(macOS)
    static func sceneKitFrameTracking() {
        let scene = SCNScene()
        let raider = SCNNode()
        raider.position = SCNVector3(10, 1, -5)
        scene.rootNode.addChildNode(raider)
        let activity = SCNNode()
        raider.addChildNode(activity)
        let cameraNull = SCNNode()
        cameraNull.name = "Camera_00"
        cameraNull.position = SCNVector3(2, 3, 4)
        activity.addChildNode(cameraNull)
        let camera = SCNNode()
        scene.rootNode.addChildNode(camera)
        raider.isHidden = true
        let fallback = SCNVector3(10, 1.68, -5)
        Tracking.synchronize(camera: camera, animatedAnchor: cameraNull,
                             fallback: fallback, heading: 0, elapsedSeconds: 0.04,
                             blockSize: 40, firstFrame: true)
        precondition(near(Double(camera.position.x), 12) &&
                     near(Double(camera.position.y), 4) &&
                     near(Double(camera.position.z), -1),
                     "Original camera null must be used on first entry even when Raider is hidden")

        cameraNull.position = SCNVector3(3, 3.25, 4)
        Tracking.synchronize(camera: camera, animatedAnchor: cameraNull,
                             fallback: fallback, heading: .pi / 2,
                             elapsedSeconds: 0.04, blockSize: 40, firstFrame: false)
        precondition(near(Double(camera.position.x), 12.2) &&
                     near(Double(camera.position.y), 4.05),
                     "Hidden animated drill frame must follow with original damping")
        let yaw = Double(camera.eulerAngles.y)
        precondition(near(cos(yaw), cos(1.5 * Double.pi)) &&
                     near(sin(yaw), sin(1.5 * Double.pi)),
                     "Preserve existing provisional yaw until retail orientation is verified")
        Tracking.synchronize(camera: camera, animatedAnchor: nil,
                             fallback: fallback, heading: 0, elapsedSeconds: 0.04,
                             blockSize: 40, firstFrame: true)
        precondition(near(Double(camera.position.y), 1.68),
                     "Absent retail null falls back to provisional eye height")
    }
    #endif
}
