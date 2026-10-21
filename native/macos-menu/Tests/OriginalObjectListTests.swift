import Foundation

@main struct OriginalObjectListTests {
    static func main() throws {
        let original = """
        ; Source-shaped retail .ol syntax
        Lego* {
            Object1 {
                type Toolstation
                xPos 11.500000
                yPos 10.500000
                heading 180.000000
                health 50.000000
            }
            Object2 {
                type Pilot
                xPos 12.500000
                yPos 11.500000
                heading 90.000000
                driving Object3
            }
            Object3 {
                type SmallDigger
                xPos 12.500000
                yPos 11.500000
                heading 90.000000
            }
            CameraStart {
                type TVCamera
                xPos 11.000000
                yPos 10.000000
                heading 45.000000
            }
        }
        """
        let cfg = try LegoConfig(text: original)
        precondition(cfg.childSections(under: ["Lego*"]) ==
            ["Object1", "Object2", "Object3", "CameraStart"])
        precondition(cfg.childSections(under: ["LEGO*"]) ==
            ["Object1", "Object2", "Object3", "CameraStart"])
        precondition(cfg.childSections(under: ["Lego*", "Object2"]).isEmpty)

        let loaded = try OriginalObjectList(data: Data(original.utf8))
        precondition(loaded.placements.count == 4)
        precondition(loaded.placements.map(\.identifier) ==
            ["Object1", "Object2", "Object3", "CameraStart"])
        precondition(loaded.rockRaiders.count == 1)
        precondition(loaded.rockRaiders[0].identifier == "Object2")
        precondition(loaded.rockRaiders[0].x == 12.5)
        precondition(loaded.rockRaiders[0].y == 11.5)
        precondition(loaded.rockRaiders[0].headingDegrees == 90)
        precondition(loaded.rockRaiders[0].drivingIdentifier == "Object3")
        precondition(loaded.placements[0].health == 50)
        precondition(loaded.initialCamera?.headingDegrees == 45)

        func rejects(_ sample: String) {
            do {
                _ = try OriginalObjectList(data: Data(sample.utf8))
                preconditionFailure("Unsafe or malformed original OL was accepted")
            } catch {}
        }
        rejects("Lego* { Object1 { type Pilot } }")
        rejects("""
        Lego* {
          Object1 {
            type Pilot
            xPos NaN
            yPos 0
            heading 0
          }
        }
        """)
        rejects("""
        Lego* {
          Object1 {
            type Pilot
            xPos 2000000
            yPos 0
            heading 0
          }
        }
        """)
        rejects("""
        Lego* {
          Object1 {
            type Pilot
            xPos 0
            yPos 0
            heading infinity
          }
        }
        """)
        print("PASS: retail OL sections, Rock Raider/camera spawns, headings, health, driving and malformed-file guards")
    }
}
