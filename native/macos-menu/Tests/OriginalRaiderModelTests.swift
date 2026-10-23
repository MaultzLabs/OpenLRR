import Foundation

@main struct OriginalRaiderModelTests {
    static func main() throws {
        let definition = try LegoConfig(text: """
        Lego* {
          Activities {
            Activity_Stand Stand
            Activity_Route Walk
          }
          Stand {
            FILE PilotStand
            LWSFILE TRUE
          }
          Walk {
            FILE PilotWalk.lws
            LWSFILE TRUE
          }
        }
        """)
        let activities = try OriginalRaiderActivities(directory: "MiniFigures\\Pilot", definition: definition)
        let stand = try activities.scenePath(activity: "Activity_Stand")
        precondition(stand == "MiniFigures/Pilot/PilotStand.lws")
        let walk = try activities.scenePath(activity: "Activity_Route")
        precondition(walk == "MiniFigures/Pilot/PilotWalk.lws")
        do {
            _ = try activities.scenePath(activity: "Activity_Drill")
            preconditionFailure("Missing animation must not become a fabricated clip")
        } catch OriginalRaiderActivities.AssetError.invalid { }
        for path in ["../Pilot", "/Pilot", "C:/Pilot", "Pilot//Parts"] {
            do {
                _ = try OriginalRaiderActivities(directory: path, definition: definition)
                preconditionFailure("Unsafe model path")
            } catch OriginalRaiderActivities.AssetError.invalid { }
        }
        print("PASS: original AE activity indirection, stand/walk paths, missing clips and invalid paths")
    }
}
