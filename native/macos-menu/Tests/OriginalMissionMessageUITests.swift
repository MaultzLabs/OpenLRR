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
        print("Original mission message CFG tests passed")
    }
}
