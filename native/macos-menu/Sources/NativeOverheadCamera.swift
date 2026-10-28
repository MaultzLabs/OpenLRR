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

/// Original Game.cpp first-person fog: level RGB, Main::FPClipBlocks,
/// and optional HighFogColourRGB oscillation in 25 Hz game-time units.
struct NativeFirstPersonFog {
    let base: [Double]
    let high: [Double]?
    let distance: Double
    let period: Double?
    init?(config: LegoConfig?, level: String) {
        let path = level.components(separatedBy: "::")
        func color(_ name: String) -> [Double]? {
            guard let value = config?.valueUnderGame(path + [name]) else { return nil }
            let parts = value.split(separator: ":").compactMap { Double($0) }
            guard parts.count == 3, parts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 255 }) else { return nil }
            return parts.map { $0 / 255 }
        }
        guard let base = color("FogColourRGB"),
              let rawDistance = config?.valueUnderGame(["Main", "FPClipBlocks"]),
              let distance = Double(rawDistance), distance.isFinite, distance > 0 else { return nil }
        self.base = base
        self.high = color("HighFogColourRGB")
        self.distance = distance // Native terrain uses blocks, not retail world units.
        if let raw = config?.valueUnderGame(path + ["FogRate"]),
           let rate = Double(raw), rate.isFinite, rate > 0 { period = rate }
        else { period = high == nil ? nil : 60 }
    }
    func color(seconds: Double) -> [Double] {
        guard let high, let period, seconds.isFinite else { return base }
        let wave = sin(seconds * 2 * .pi / period)
        return zip(base, high).map { min(1, max(0, $0 + ($1 - $0) * 0.5 * wave)) }
    }
}
