import Foundation

@main struct OriginalMissionMessageUITests {
    static func main() throws {
        let fogConfig = try LegoConfig(text: """
        Lego* {
          Main {
            FPClipBlocks 12
          }
          Levels {
            Level01 {
              FogColourRGB 40:60:80
              HighFogColourRGB 80:100:120
              FogRate 8
            }
          }
        }
        """)
        let fog = NativeFirstPersonFog(config: fogConfig, level: "Levels::Level01")!
        precondition(fog.distance == 12 && fog.period == 8)
        precondition(abs(fog.color(seconds: 2)[0] - 60.0 / 255) < 0.000001)
        precondition(NativeFirstPersonFog(config: nil, level: "Levels::Level01") == nil)
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
            InterfaceBackButton 40:20:Interface/BackHL.bmp:Interface/BackPR.bmp:Go_Back
            InterfaceBuildImages { ToolStation Tool_Store:SFX_Okay:Interface/Tool.bmp }
            InterfaceSurroundImages {
                4 Interface/BackPanel.bmp:-24:-8:-31:233:Interface/MainPanel.bmp:-19:7
                1 Interface/BackPanel.bmp:-24:-8:-31:233:Interface/FirstPerson.bmp:-12:-4
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
        precondition(catalog.backButton?.size == CGSize(width: 40, height: 20))
        precondition(catalog.backButton?.title == "Go Back")
        precondition(OriginalMissionCommandCatalog(config: nil).backButton == nil)
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
        let backSurround = catalog.surround(count: 4, hasBack: true)!
        let mainSurround = catalog.surround(count: 4, hasBack: false)!
        precondition(backSurround.artOffset == CGPoint(x: -24, y: -8))
        precondition(backSurround.back == CGPoint(x: -31, y: 233))
        precondition(mainSurround.image == "Interface/MainPanel.bmp")
        precondition(mainSurround.artOffset == CGPoint(x: -19, y: 7))
        precondition(mainSurround.back == nil)
        precondition(!OriginalMissionCommandCatalog.Page.main.showsBack)
        precondition(!OriginalMissionCommandCatalog.Page.firstPerson.showsBack)
        precondition([OriginalMissionCommandCatalog.Page.wall, .raider, .buildings].allSatisfy { $0.showsBack })
        let iconSizes = [CGSize(width: 40, height: 13), CGSize(width: 44, height: 27),
                         CGSize(width: 81, height: 150), CGSize(width: 67, height: 19)]
        let commandLayout = OriginalMissionCommandLayout(iconSizes: iconSizes,
            surround: backSurround, surroundSize: CGSize(width: 90, height: 260),
            backSize: CGSize(width: 40, height: 20), showsBack: true)
        precondition(commandLayout.icons == [CGRect(x: 565, y: 18, width: 40, height: 13),
            CGRect(x: 565, y: 31, width: 44, height: 27), CGRect(x: 565, y: 58, width: 81, height: 150),
            CGRect(x: 565, y: 208, width: 67, height: 19)], "Bitmap dimensions must not be capped or displaced by surround offsets")
        precondition(commandLayout.surround == CGRect(x: 541, y: 10, width: 90, height: 260))
        precondition(commandLayout.back == CGRect(x: 534, y: 251, width: 40, height: 20))
        let mainLayout = OriginalMissionCommandLayout(iconSizes: iconSizes,
            surround: mainSurround, surroundSize: CGSize(width: 90, height: 260),
            backSize: CGSize(width: 40, height: 20), showsBack: false)
        precondition(mainLayout.icons == commandLayout.icons)
        precondition(mainLayout.surround == CGRect(x: 546, y: 25, width: 90, height: 260))
        precondition(mainLayout.back == nil)
        let fpLayout = OriginalMissionCommandLayout(iconSizes: [CGSize(width: 41, height: 31)],
            surround: catalog.surround(count: 1, hasBack: OriginalMissionCommandCatalog.Page.firstPerson.showsBack),
            surroundSize: CGSize(width: 83, height: 51), backSize: CGSize(width: 40, height: 20), showsBack: false)
        precondition(fpLayout.surround == CGRect(x: 553, y: 14, width: 83, height: 51))
        precondition(fpLayout.back == nil)
        precondition(catalog.surround(count: 2, hasBack: true) == nil)
        precondition(catalog.surround(count: 12, hasBack: true) == nil)
        let panelConfig = try LegoConfig(text: """
        Lego* {
            Main {
                MinTilt 20
                MaxTilt 70
                MinDist 80
                MaxDist 400
            }
            Panels640x480 {
                Panel_CameraControl Interface/Camera.bmp,410,410,410,410
                Panel_CrystalSideBar Interface/Side.bmp,584,0,584,0
                Panel_PriorityList Interface/Priority.bmp,398,50,640,50
            }
            PanelRotationControl {
                CenterPositionX 484
                CenterPositionY 445
                Radius 30
                LeftImage Interface/Left.bmp,460,438
            }
        }
        """)
        let panels = OriginalMissionPanelDefinition.load(panelConfig)
        precondition(panels.count == 2, "Do not render unimplemented sliding windows open")
        precondition(panels[0].open == CGPoint(x: 410, y: 410))
        precondition(OriginalMissionPanelDefinition.parse(name: "x", value: "x.bmp,0,nan,0,0") == nil)
        for (size, scale, origin) in [
            (CGSize(width: 640, height: 480), CGFloat(1), CGPoint.zero),
            (CGSize(width: 1280, height: 960), CGFloat(2), CGPoint.zero),
            (CGSize(width: 1600, height: 960), CGFloat(2), CGPoint(x: 160, y: 0)),
            (CGSize(width: 640, height: 960), CGFloat(1), CGPoint(x: 0, y: 480))
        ] {
            let transform = OriginalHUDTransform(size: size)
            precondition(transform.scale == scale && transform.origin == origin)
            for rect in commandLayout.icons + [commandLayout.surround!, commandLayout.back!,
                                                CGRect(x: 584, y: 0, width: 56, height: 480)] {
                let screen = transform.screen(rect)
                precondition(screen.origin == CGPoint(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale))
                precondition(screen.size == CGSize(width: rect.width * scale, height: rect.height * scale))
                precondition(transform.logical(screen.origin) == rect.origin, "Drawing and hit testing share the panel transform")
            }
        }
        let rotation = OriginalRotationControl(config: panelConfig)!
        precondition(rotation.contains(CGPoint(x: 484, y: 445)))
        precondition(!rotation.contains(CGPoint(x: 515, y: 445)))
        precondition(rotation.normalized(CGPoint(x: 544, y: 445)) == CGPoint(x: 1, y: 0))
        precondition(rotation.overlays["Left"]?.position == CGPoint(x: 460, y: 438))
        let camera = NativeOverheadCamera(config: panelConfig, blockSize: 40)
        precondition(camera.distanceRange == 2...10)
        let moved = camera.moved(offset: .init(x: 0, y: 5, z: 5), horizontal: 1, vertical: 0, zoom: 0, seconds: 0.04)
        precondition(abs(atan2(moved.x, moved.z) + 0.02) < 0.00001)
        let zoomed = camera.moved(offset: .init(x: 0, y: 5, z: 5), horizontal: 0, vertical: 0, zoom: 1, seconds: 0.04)
        precondition(abs(sqrt(zoomed.y * zoomed.y + zoomed.z * zoomed.z) - sqrt(50) - 0.075) < 0.00001)
        let bounded = camera.moved(offset: .init(x: 0, y: 500, z: 0), horizontal: 0, vertical: -1, zoom: 1, seconds: 500)
        precondition(abs(sqrt(bounded.y * bounded.y + bounded.z * bounded.z) - 10) < 0.00001)
        precondition(abs(acos(bounded.y / 10) - 20 * Double.pi / 180) < 0.00001)
        let widths = [Int](repeating: 5, count: 190)
        precondition(OriginalFontLayout.wrap("AB CD", characterWidths: widths, width: 20) == "AB\nCD")
        precondition(OriginalFontLayout.wrap("ABCDE", characterWidths: widths, width: 20) == "ABC\nDE")
        precondition(OriginalFontLayout.wrap("A\nB", characterWidths: widths, width: 20) == "A\nB")
        precondition(OriginalFontLayout.wrap("A\u{7}hidden", characterWidths: widths, width: 20) == "A")
        print("Original mission message and command CFG tests passed")
    }
}
