import Foundation
#if os(macOS)
import SceneKit
#endif

@main struct NativeFirstPersonCameraTrackingTests {
    typealias Tracking = NativeFirstPersonCameraTracking

    static func near(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

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
        #if os(macOS)
        sceneKitFrameTracking()
        #endif
        print("PASS: original camera-null position priority, nonfinite safety, drilling-frame tracking")
    }

    #if os(macOS)
    static func sceneKitFrameTracking() {
        // Synthetic ACT hierarchy: the view hides its controlled Raider while
        // the original animated LWS null must still drive the separate camera.
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
                             fallback: fallback, heading: 0)
        precondition(near(Double(camera.position.x), 12) &&
                     near(Double(camera.position.y), 4) &&
                     near(Double(camera.position.z), -1),
                     "First-person camera follows named LWS camera frame even when Raider hidden")

        // Stand -> Drill frame movement is not keyboard movement; the camera
        // must still follow the changed world transform in the next frame.
        cameraNull.position = SCNVector3(3, 6, 8)
        Tracking.synchronize(camera: camera, animatedAnchor: cameraNull,
                             fallback: fallback, heading: .pi / 2)
        precondition(near(Double(camera.position.x), 13) &&
                     near(Double(camera.position.y), 7) &&
                     near(Double(camera.position.z), 3),
                     "Camera follows animated drill frame independent of player locomotion")
        let yaw = Double(camera.eulerAngles.y)
        precondition(near(cos(yaw), cos(1.5 * Double.pi)) &&
                     near(sin(yaw), sin(1.5 * Double.pi)),
                     "Preserve existing controller yaw until original camera orientation is validated")

        Tracking.synchronize(camera: camera, animatedAnchor: nil,
                             fallback: fallback, heading: 0)
        precondition(near(Double(camera.position.y), 1.68),
                     "Unavailable camera null still uses explicit provisional eye height")
        // Nonfinite transforms are exercised in the portable pose test.
        // Avoid feeding infinities into SceneKit's unmanaged presentation tree.
    }
    #endif
}
