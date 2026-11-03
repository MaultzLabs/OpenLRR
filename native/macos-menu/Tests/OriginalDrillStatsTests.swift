import Foundation

@main
struct OriginalDrillStatsTests {
    static func main() throws {
        let config = try LegoConfig(text: """
        Lego* {
          Stats {
            Pilot {
              LooseDrillTime 2.5:1.2:0.8
              MedDrillTime 4.25:2
              HardDrillTime 10
              SeamDrillTime 6.5:3
              DrillSound SFX_MiniDrill
              DrillFadeSound SFX_MiniDrillFade
            }
          }
          Samples {
            SFX_MiniDrill Sounds/MiniDrill
            SFX_MiniDrillFade Sounds/MiniDrillFade
          }
        }
        """)
        let stats = OriginalDrillStats(config: config)
        precondition(stats.seconds(forTerrainCode: 4) == 2.5)
        precondition(stats.seconds(forTerrainCode: 5) == 2.5) // Soil remapped to Loose.
        precondition(stats.seconds(forTerrainCode: 3) == 4.25)
        precondition(stats.seconds(forTerrainCode: 8) == 6.5)
        precondition(stats.seconds(forTerrainCode: 10) == 6.5)
        for code: UInt16 in [0, 1, 2, 6, 11, 255] {
            precondition(stats.seconds(forTerrainCode: code) == nil)
        }
        precondition(stats.soundIdentifier(fade: false) == "SFX_MiniDrill")
        precondition(stats.soundIdentifier(fade: true) == "SFX_MiniDrillFade")
        let unregistered = try LegoConfig(text: """
        Lego* {
          Stats { Pilot { DrillSound SFX_UnknownDrill } }
        }
        """)
        precondition(OriginalDrillStats(config: unregistered).soundIdentifier(fade: false) == "SFX_Drill")

        let invalid = try LegoConfig(text: """
        Lego* {
          Stats { Pilot {
            LooseDrillTime NaN
            MedDrillTime -2
            SeamDrillTime 0
          } }
        }
        """)
        let fallback = OriginalDrillStats(config: invalid)
        precondition(fallback.seconds(forTerrainCode: 4) == nil)
        precondition(fallback.seconds(forTerrainCode: 3) == nil)
        precondition(fallback.seconds(forTerrainCode: 8) == nil)
        precondition(fallback.soundIdentifier(fade: false) == "SFX_Drill")
        precondition(fallback.soundIdentifier(fade: true) == "SFX_DrillFade")

        let missing = try LegoConfig(text: "Lego* { Main { SoundOn TRUE } }")
        precondition(OriginalDrillStats(config: missing).seconds(forTerrainCode: 4) == nil)
        print("OriginalDrillStatsTests passed: terrain, level-zero stats, invalid times, source sound IDs")
    }
}
