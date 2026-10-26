import Foundation

@main struct OriginalMissionMessageUITests {
    static func main() throws {
        let config = try LegoConfig(text: """
        Lego* {
            Main {
                NextButton640x480 Interface\\MessagePanel\\OK.bmp
                NextButtonPos640x480 380,447
            }
            Panels640x480 {
                Panel_Messages Interface\\MessagePanel\\MsgPanel.bmp,0,0,0,0
            }
        }
        """)
        let ui = OriginalMissionMessageDefinition(config: config)
        precondition(ui.panelPath == "Interface\\MessagePanel\\MsgPanel.bmp")
        precondition(ui.nextPath == "Interface\\MessagePanel\\OK.bmp")
        precondition(ui.nextPosition == CGPoint(x: 380, y: 447))
        precondition(OriginalMissionMessageDefinition(config: nil).nextPosition == nil)
        for value in ["", "380", "380,", "1,2,3", "nan,1", "1,inf", "99999,0"] {
            precondition(OriginalMissionMessageDefinition.point(value) == nil, value)
        }
        precondition(OriginalMissionMessageDefinition.point(" -20, 0 ") == CGPoint(x: -20, y: 0))
        precondition(OriginalMissionMessageDefinition.firstBitmapPath("Drill:SFX_Dig:Interface/Dig.bmp:Interface/PDig.bmp") == "Interface/Dig.bmp")
        precondition(OriginalMissionMessageDefinition.firstBitmapPath(nil) == nil)
        precondition(OriginalMissionMessageDefinition.firstBitmapPath("Drill:SFX_Dig") == nil)
        let catalogConfig = try LegoConfig(text: """
        Lego* {
            BuildingTypes {
                ToolStation Buildings/ToolStation
                TeleportPad Buildings/TeleportPad
                ToolStation IgnoredDuplicate
                Nested { NotABuilding ignored }
            }
            ObjectNames { ToolStation Tool_Store }
            Stats {
                ToolStation {
                    CostOre 5
                    CostCrystal 0
                }
            }
            InterfaceBuildImages { ToolStation Tool_Store:SFX_Okay:Interface/Tool.bmp }
            InterfaceSurroundImages {
                4 Interface/BackPanel.bmp:10:22:8:240:Interface/MainPanel.bmp:11:23
                2 Broken.bmp:nan:22:8:240
            }
        }
        Lego {
            BuildingTypes {
                ToolStation WrongPriority
                PowerStation Buildings/Power
            }
        }
        """)
        let catalog = OriginalMissionCommandCatalog(config: catalogConfig)
        let buildings = catalog.commands(on: .buildings, hasRaider: false)
        precondition(buildings.map(\.id) == ["building:toolstation", "building:teleportpad", "building:powerstation"])
        precondition(buildings[0].title == "Tool Store")
        precondition(buildings[0].detail.contains("5 ore · 0 crystals"))
        precondition(buildings[0].iconPath == "Interface/Tool.bmp")
        precondition(buildings.allSatisfy { !$0.enabled })
        precondition(catalogConfig.settingsUnderGame(["BuildingTypes"])[0].value == "Buildings/ToolStation")
        precondition(catalog.commands(on: .main, hasRaider: false)[1].enabled)
        precondition(!OriginalMissionCommandCatalog(config: nil).commands(on: .main, hasRaider: false)[1].enabled)
        precondition(!catalog.commands(on: .wall, hasRaider: false)[0].enabled)
        precondition(catalog.commands(on: .wall, hasRaider: true)[0].enabled)
        precondition(catalog.commands(on: .firstPerson, hasRaider: true)[0].id == "GotoTopView")
        precondition(catalog.surround(count: 4, hasBack: true)?.back == CGPoint(x: 8, y: 240))
        precondition(catalog.surround(count: 4, hasBack: false)?.image == "Interface/MainPanel.bmp")
        precondition(catalog.surround(count: 4, hasBack: false)?.icons == CGPoint(x: 11, y: 23))
        precondition(catalog.surround(count: 2, hasBack: true) == nil)
        precondition(catalog.surround(count: 12, hasBack: true) == nil)
        print("Original mission message and command CFG tests passed")
    }
}
