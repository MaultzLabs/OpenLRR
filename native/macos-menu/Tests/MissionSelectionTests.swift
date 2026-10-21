import Foundation

@main struct MissionSelectionTests {
    static func main() throws {
        let config = try LegoConfig(text: """
        Lego* {
          Main {
            StartLevel Levels::Level01
            TutorialStartLevel Levels::Tutorial01
          }
          Levels {
            Level01 {
              FullName Driller_Night
              NextLevel Levels::Level02
              LevelLinks Levels::Level03,Levels::Level02
              MenuBMP Interface\\FrontEnd\\AHi.bmp,Interface\\FrontEnd\\ADark.bmp,Interface\\FrontEnd\\ALocked.bmp
              FrontEndX 72
              FrontEndY 2
            }
            Level02 {
              FullName Locked_Level
              NextLevel Levels::Level03
              LevelLinks Levels::Level03
              MenuBMP Interface\\FrontEnd\\BHi.bmp,Interface\\FrontEnd\\BDark.bmp,Interface\\FrontEnd\\BLocked.bmp
              FrontEndX -80
            }
            Level03 {
              FullName Open_Training_Style
              FrontEndOpen TRUE
              LevelLinks Levels::Level01
              MenuBMP Interface\\FrontEnd\\CHi.bmp,Interface\\FrontEnd\\CDark.bmp,Interface\\FrontEnd\\CLocked.bmp
              FrontEndY 99
            }
            Tutorial01 {
              FullName First_Lesson
              NextLevel Levels::Tutorial02
              LevelLinks Levels::Tutorial02
              MenuBMP Interface\\FrontEnd\\T1Hi.bmp,Interface\\FrontEnd\\T1Dark.bmp,Interface\\FrontEnd\\T1Locked.bmp
            }
            Tutorial02 {
              FullName Second_Lesson
              MenuBMP Interface\\FrontEnd\\T2Hi.bmp,Interface\\FrontEnd\\T2Dark.bmp,Interface\\FrontEnd\\T2Locked.bmp
            }
          }
        }
        """)
        let catalog = try LevelCatalog(config: config)
        let selection = MissionSelection(config: config, catalog: catalog)

        // The graphic menu traverses LevelLinks (depth first), NOT the linear
        // NextLevel catalogue; repeat and cyclic links must not duplicate icons.
        precondition(selection.missions.map(\.identifier) ==
                     ["Levels::Level01", "Levels::Level03", "Levels::Level02"])
        precondition(selection.missions.map(\.title) ==
                     ["Driller Night", "Open Training Style", "Locked Level"])
        precondition(selection.missions.map(\.initiallyAvailable) == [true, true, false])
        precondition(selection.missions[0].x == 72 && selection.missions[0].y == 2)
        precondition(selection.missions[1].x == 0 && selection.missions[1].y == 99)
        precondition(selection.missions[2].x == -80)
        precondition(selection.missions[0].imagePaths.count == 3)
        precondition(selection.missions[0].imagePaths[0].hasSuffix("AHi.bmp"))
        precondition(selection.missions[0].imagePaths[1].hasSuffix("ADark.bmp"))
        precondition(selection.missions[0].imagePaths[2].hasSuffix("ALocked.bmp"))
        precondition(selection.tutorials.map(\.identifier) ==
                     ["Levels::Tutorial01", "Levels::Tutorial02"])
        precondition(selection.tutorials.map(\.initiallyAvailable) == [true, false])

        // Missions without a LevelLinks relationship cannot be reached by the
        // original selection traversal. Do not fabricate visible missions.
        let noLinks = try LegoConfig(text: """
        Lego* {
          Main {
            StartLevel Levels::Level01
          }
          Levels {
            Level01 {
              NextLevel Levels::Level02
              FullName One
            }
            Level02 {
              FullName Two
            }
          }
        }
        """)
        let noLinksCatalog = try LevelCatalog(config: noLinks)
        precondition(MissionSelection(config: noLinks, catalog: noLinksCatalog).missions.count == 1)

        print("PASS: original LevelLinks ordering, icon variants, root/open/locked flags, cycles and tutorials")
    }
}
