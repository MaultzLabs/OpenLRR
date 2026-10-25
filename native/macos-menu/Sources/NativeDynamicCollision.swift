import Foundation

/// Swept horizontal footprint checks against other original OL Rock Raiders.
/// Positions come from the live scene markers; unlike terrain, other Raiders
/// can move between frames. The radii are conservative native-prototype
/// clearances, not measurements of the original game's collision shapes.
struct NativeDynamicCollision {
    struct Point {
        let x: Double
        let y: Double
    }

    struct Disc {
        let center: Point
        let radius: Double
    }

    static let controlledRaiderRadius = 0.23
    static let otherRaiderRadius = 0.22
    static let maximumObstacles = 200 // OriginalObjectList.maximumObjects.

    /// Continuous segment-to-disc distance prevents a long frame from
    /// tunnelling through a second Raider. If two original OL spawns already
    /// overlap, strictly separating motion is allowed to escape the overlap.
    static func sweepIsClear(from a: Point, to b: Point,
                             obstacles: [Disc],
                             movingRadius: Double = controlledRaiderRadius) -> Bool {
        guard movingRadius.isFinite, movingRadius > 0,
              [a.x, a.y, b.x, b.y].allSatisfy({ $0.isFinite }),
              obstacles.count <= maximumObstacles else { return false }
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard dx.isFinite, dy.isFinite, lengthSquared.isFinite else { return false }

        for obstacle in obstacles {
            guard obstacle.center.x.isFinite, obstacle.center.y.isFinite,
                  obstacle.radius.isFinite, obstacle.radius >= 0 else { return false }
            let combinedRadius = movingRadius + obstacle.radius
            let radiusSquared = combinedRadius * combinedRadius
            let sx = a.x - obstacle.center.x
            let sy = a.y - obstacle.center.y
            let startSquared = sx * sx + sy * sy
            let toward = sx * dx + sy * dy
            guard radiusSquared.isFinite, startSquared.isFinite, toward.isFinite else { return false }

            if startSquared < radiusSquared {
                // Never trap a Raider inside an overlapping original spawn:
                // permit motion away, but not sideways or deeper inside it.
                let endSquared = (sx + dx) * (sx + dx) + (sy + dy) * (sy + dy)
                guard endSquared.isFinite, toward >= 0,
                      endSquared > startSquared else { return false }
                continue
            }

            let fraction = lengthSquared > 0 ?
                max(0, min(1, -toward / lengthSquared)) : 0
            let closestX = sx + fraction * dx
            let closestY = sy + fraction * dy
            let closestSquared = closestX * closestX + closestY * closestY
            guard closestSquared.isFinite, closestSquared >= radiusSquared else { return false }
        }
        return true
    }
}
