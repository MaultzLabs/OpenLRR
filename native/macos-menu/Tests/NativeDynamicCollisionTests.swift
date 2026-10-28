import Foundation

@main struct NativeDynamicCollisionTests {
    static func main() {
        typealias Collision = NativeDynamicCollision
        func point(_ x: Double, _ y: Double) -> Collision.Point { .init(x: x, y: y) }
        func raider(_ x: Double, _ y: Double, _ radius: Double = Collision.otherRaiderRadius) -> Collision.Disc {
            .init(center: point(x, y), radius: radius)
        }
        func clear(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
                   _ obstacles: [Collision.Disc]) -> Bool {
            Collision.sweepIsClear(from: point(x0, y0), to: point(x1, y1), obstacles: obstacles)
        }

        precondition(clear(0, 0, 2, 0, []))
        precondition(!clear(0, 0, 2, 0, [raider(1, 0)])) // Endpoints clear, swept path blocked.
        precondition(clear(0, 1, 2, 1, [raider(1, 0)]))
        precondition(clear(0, 0.45, 2, 0.45, [raider(1, 0)])) // Tangent contact.
        precondition(!clear(0, 0.44, 2, 0.44, [raider(1, 0)]))
        precondition(!clear(0, 0, 1, 1, [raider(0.5, 0.5)])) // Diagonal crossing.
        precondition(clear(0, 0, 0.25, 0, [raider(-0.1, 0)])) // Escape overlap.
        precondition(!clear(0, 0, -0.1, 0, [raider(-0.1, 0)])) // Deeper overlap.
        precondition(!clear(0, 0, 0, 0, [raider(0, 0)])) // No stationary overlap.
        precondition(!clear(0, 0, 1, 0, [raider(0.8, 0), raider(10, 10)]))
        precondition(clear(0, 0, 1, 0, [raider(3, 0), raider(10, 10)]))
        precondition(!clear(.nan, 0, 1, 0, []))
        precondition(!clear(0, 0, 1, 0, [raider(1, 0, .nan)]))
        precondition(!clear(0, 0, 1, 0, [raider(1, 0, -1)]))
        precondition(!clear(0, 0, 1, 0, Array(repeating: raider(10, 10), count: 201)))
        precondition(!Collision.sweepIsClear(from: point(0, 0), to: point(1, 0),
                                                   obstacles: [], movingRadius: .infinity))
        print("PASS: swept Raider collision, tangent, escape, moving obstacles and invalid data")
    }
}
