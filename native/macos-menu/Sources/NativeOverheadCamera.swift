import Foundation

/// GameState.cpp camera shortcuts use 0.02 radians and 3 distance units per
/// standard (25 Hz) tick. Distance is converted into native map-block units.
struct NativeOverheadCamera {
    let blockSize: Double
    let tiltRange: ClosedRange<Double>
    let distanceRange: ClosedRange<Double>
    init(config: LegoConfig?, blockSize: Double) {
        self.blockSize = blockSize.isFinite && blockSize > 0 ? blockSize : 40
        func number(_ key: String) -> Double? {
            guard let raw = config?.valueUnderGame(["Main", key]), let value = Double(raw), value.isFinite else { return nil }
            return value
        }
        let minTilt = max(0, min(89, number("MinTilt") ?? 0)) * .pi / 180
        let maxTilt = max(0, min(89, number("MaxTilt") ?? 85)) * .pi / 180
        tiltRange = min(minTilt, maxTilt)...max(minTilt, maxTilt)
        let near = max(0.1, (number("MinDist") ?? 40) / self.blockSize)
        let far = max(near, (number("MaxDist") ?? 1600) / self.blockSize)
        distanceRange = near...far
    }
    struct Offset { let x: Double; let y: Double; let z: Double }
    func moved(offset: Offset, horizontal: Double, vertical: Double, zoom: Double, seconds: Double) -> Offset {
        let elapsed = max(0, min(0.05, seconds.isFinite ? seconds : 0)) * 25
        let distance = max(0.001, sqrt(offset.x * offset.x + offset.y * offset.y + offset.z * offset.z))
        let oldTilt = acos(max(-1, min(1, offset.y / distance)))
        let tilt = max(tiltRange.lowerBound, min(tiltRange.upperBound, oldTilt + vertical * elapsed * 0.02))
        let angle = atan2(offset.x, offset.z) - horizontal * elapsed * 0.02
        let radius = max(distanceRange.lowerBound, min(distanceRange.upperBound, distance + zoom * elapsed * 3 / blockSize))
        return Offset(x: sin(angle) * sin(tilt) * radius, y: cos(tilt) * radius, z: cos(angle) * sin(tilt) * radius)
    }
}
