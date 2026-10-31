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
        directionRegression()
        #if os(macOS)
        sceneKitFrameTracking()
        #endif
        print("PASS: original camera-null fallback, Camera_Update position and direction damping, turn snap, animated drill tracking")
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


    static func directionRegression() {
        let quarter = Double.pi / 2
        let first = Tracking.smoothedHeading(current: nil, target: quarter,
                                             elapsedSeconds: 0.04)
        precondition(near(first, quarter), "Initial camera facing must snap")
        let eased = Tracking.smoothedHeading(current: 0, target: quarter,
                                             elapsedSeconds: 0.04)
        precondition(near(eased, atan2(1, 4)), "Retail 4:1 direction-vector blend")
        precondition(!Tracking.requiresDirectionSnap(current: 0, target: quarter))
        precondition(Tracking.requiresDirectionSnap(current: 0, target: .pi))
        precondition(near(Tracking.smoothedHeading(current: 0, target: .pi,
                          elapsedSeconds: 0.04), .pi), "Reversed view direction snaps")
        let crossing = Tracking.smoothedHeading(current: .pi - 0.1,
                                               target: -.pi + 0.1, elapsedSeconds: 0.04)
        precondition(abs(abs(crossing) - .pi) < 0.12,
                     "A small turn across the +/-pi wrap must not spin around")
        precondition(Tracking.smoothedHeading(current: 0.4, target: 0.40001,
                      elapsedSeconds: 0.04) == 0.4, "Ignore subthreshold angular jitter")
        precondition(Tracking.smoothedHeading(current: 0.4, target: 1.2,
                      elapsedSeconds: 0) == 0.4)
        precondition(Tracking.smoothedHeading(current: 0.4, target: 1.2,
                      elapsedSeconds: .nan) == 0.4)
        precondition(Tracking.smoothedHeading(current: 0.4, target: .nan,
                      elapsedSeconds: 0.04) == 0.4)
        precondition(near(Tracking.smoothedHeading(current: nil, target: 2 * .pi,
                         elapsedSeconds: 0.04), 0), "Initial yaw normalizes")
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
        precondition(near(cos(yaw), cos(.pi + atan2(1, 4))) &&
                     near(sin(yaw), sin(.pi + atan2(1, 4))),
                     "Camera direction uses original 4:1 vector smoothing")
        cameraNull.position = SCNVector3(3.5, 3.5, 4)
        Tracking.synchronize(camera: camera, animatedAnchor: cameraNull,
                             fallback: fallback, heading: -.pi / 2,
                             elapsedSeconds: 0.04, blockSize: 40, firstFrame: false)
        precondition(near(Double(camera.position.x), 13.5),
                     "Reversing facing by more than 90 degrees snaps position too")
        Tracking.synchronize(camera: camera, animatedAnchor: nil,
                             fallback: fallback, heading: 0, elapsedSeconds: 0.04,
                             blockSize: 40, firstFrame: true)
        precondition(near(Double(camera.position.y), 1.68),
                     "Absent retail null falls back to provisional eye height")
    }
    #endif
}
