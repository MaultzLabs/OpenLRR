import Foundation

@main struct OriginalRaiderCollisionTests {
    static func main() throws {
        func config(_ stats: String) throws -> LegoConfig {
            try LegoConfig(text: """
            Lego* {
              Stats {
                Pilot {
            \(stats)
                }
              }
            }
            """)
        }
        func radius(_ config: LegoConfig?, blockSize: Double = 40) -> Double {
            OriginalRaiderCollision.tileRadius(config: config, blockSize: blockSize)
        }
        func expect(_ value: Double, _ expected: Double) {
            precondition(abs(value - expected) < 0.00000001,
                         "Expected \(expected) tiles but got \(value)")
        }

        expect(radius(try config("CollRadius 8")), 0.2)
        expect(radius(try config("CollRadius 8\nCollBox 100,100")), 0.2)
        expect(radius(try config("CollRadius 0\nCollBox 12,8")), 0.15)
        expect(radius(try config("CollBox 10,16")), 0.2)
        expect(radius(try config("CollBox 10,16"), blockSize: 80), 0.1)
        expect(radius(try config("CollRadius 10"), blockSize: 100), 0.1)

        for stats in ["CollRadius -2", "CollRadius NaN", "CollRadius infinity",
                      "CollRadius 0", "CollRadius 50", "CollBox 12",
                      "CollBox -4,8", "CollBox 0,8", "CollBox x,8",
                      "CollBox 8,infinity"] {
            expect(radius(try config(stats)), OriginalRaiderCollision.provisionalFallback)
        }
        expect(radius(nil), OriginalRaiderCollision.provisionalFallback)
        expect(radius(try config("CollRadius 8"), blockSize: 0), OriginalRaiderCollision.provisionalFallback)
        expect(radius(try config("CollRadius 8"), blockSize: .nan), OriginalRaiderCollision.provisionalFallback)
        expect(radius(try config("CollRadius 8"), blockSize: .infinity), OriginalRaiderCollision.provisionalFallback)

        print("PASS: original Pilot CollRadius, CollBox, game BlockSize and safe fallback")
    }
}
