import Foundation

private func le(_ n: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
     UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
}
private func archive(_ files: [(String, [UInt8])]) -> Data {
    var b: [UInt8] = [87, 87, 65, 68] + le(UInt32(files.count))
    for (name, _) in files { b += Array(name.utf8) + [0] }
    for (name, _) in files { b += Array(("C:\\Build\\" + name).utf8) + [0] }
    let start = b.count + files.count * 16
    var offset = start
    for (_, value) in files {
        b += le(1) + le(UInt32(value.count)) + le(UInt32(value.count)) + le(UInt32(offset))
        offset += value.count
    }
    for (_, value) in files { b += value }
    return Data(b)
}
private func failure(_ label: String, _ run: () throws -> Void) {
    var wasRejected = false
    do { try run() }
    catch { wasRejected = true }
    precondition(wasRejected, "Expected failure: \(label)")
    print("Expected rejection: \(label)")
}
@main struct NativeCoreTests {
    static func main() throws {
        let cfg = """
        ; Mirrors the original Lego.cfg hierarchical group layout
        Lego* {
          Menu {
            MainMenuFull {
              MenuCount 2
              Menu1 {
                Title Main_Menu
                FullName Main_Menu
                Position 100:55
                MenuImage Interface\\FrontEnd\\MenuBGpic.bmp
                ItemCount 3
                Item1 Next:20:30:Play_Game:Menu2
                Item2 Next:20:70:Interface\\FrontEnd\\ButtonLo.bmp:Interface\\FrontEnd\\ButtonHi.bmp:Unused:TT:Menu2
                Item3 Trigger:20:120:Exit:1
              }
              Menu2 {
                Title Select_Level
                Position 55:40
                ItemCount 1
                Item1 Next:10:10:Back:Menu1
              }
            }
          }
        }
        """
        let wad0 = archive([("Interface\\FrontEnd\\MenuBGpic.bmp", [66,77,0,0])])
        let wad1 = archive([("Lego.cfg", Array(cfg.utf8)),
                            ("Interface\\FrontEnd\\MenuBGpic.bmp", [66,77,1,1])])
        let resources = try GameResources(archives: [(0,wad0),(1,wad1)])
        precondition(resources.mountedIndices == [1,0])
        let picked = try resources.data(at: "Interface/FrontEnd/MenuBGpic.bmp")
        precondition(picked == Data([66,77,1,1]))
        precondition(resources.exists("Lego.cfg"))
        precondition(resources.list(prefix: "Interface/FrontEnd").count == 1)
        let parsed = try LegoConfig(data: resources.configData())
        precondition(parsed.valueUnderGame(["Menu","MainMenuFull","Menu1","Title"]) == "Main_Menu")
        let menus = try MenuDefinition(config:parsed)
        precondition(menus.menus.count == 2)
        precondition(menus.menus[0].title == "Main Menu")
        precondition(menus.menus[0].x == 100 && menus.menus[0].y == 55)
        precondition(menus.menus[0].items.count == 3)
        precondition(menus.menus[0].items[0].linkedMenu == 1)
        precondition(menus.menus[0].items[0].caption == "Play Game")
        precondition(menus.menus[0].items[1].imageNormal == "Interface\\FrontEnd\\ButtonLo.bmp")
        precondition(menus.menus[0].items[1].linkedMenu == 1)
        precondition(menus.menus[1].items[0].linkedMenu == 0)
        failure("duplicate archive indexes") { _ = try GameResources(archives:[(0,wad0),(0,wad1)]) }
        failure("missing asset") { _ = try resources.data(at:"missing.bmp") }
        failure("unbalanced braces") { _ = try LegoConfig(text:"Lego* { Menu { x v }") }
        failure("unknown MenuCount") { _ = try MenuDefinition(config:LegoConfig(text:"Lego* { x value }")) }
        let levels = try LegoConfig(text: """
        Lego* {
          Main {
            StartLevel Levels::Level01
            TutorialStartLevel Levels::Tutorial01
          }
          Levels {
            Level01 {
              FullName Driller_Night
              NextLevel Levels::Level02
              MenuBMP Interface\\FrontEnd\\CRock.bmp,Interface\\FrontEnd\\CRockHi.bmp
              FrontEndX 72
              FrontEndY 2
            }
            Level02 {
              FullName The_Path_To_Power
            }
            Tutorial01 {
              FullName Tutorial_Mission
            }
          }
        }
        """)
        let catalog = try LevelCatalog(config: levels)
        precondition(catalog.missions.map(\.fullName) == ["Driller Night", "The Path To Power"])
        precondition(catalog.missions[0].positionX == 72)
        precondition(catalog.missions[0].menuBitmapPaths.count == 2)
        precondition(catalog.tutorials.count == 1)
        let cycle = try LegoConfig(text: """
        Lego* { Main { StartLevel Levels::Level01 }
          Levels { Level01 { NextLevel Levels::Level01 } } }
        """)
        failure("cyclic NextLevel") { _ = try LevelCatalog(config:cycle) }
        let width: UInt32 = 3, height: UInt32 = 2
        let values: [UInt16] = [3,5,7,11,13,17]
        let tileBytes: [UInt8] = values.flatMap { v in
            [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8)]
        }
        let map = Data([77,65,80,32] + le(8+width*height*2) + le(width) + le(height) + tileBytes)
        let parsedMap = try RockRaidersMap(data: map)
        precondition(parsedMap.cellCount == 6 && parsedMap.value(x: 2, y: 1) == 17)
        precondition(parsedMap.value(x: 3, y: 0) == nil)
        failure("truncated MAP") { _ = try RockRaidersMap(data: Data(map.dropLast())) }
        failure("MAP width mismatch") {
            _ = try RockRaidersMap(data: Data([77,65,80,32] + le(20) + le(4) + le(2) + tileBytes))
        }
        // Synthetic 10x19 indexed bitmap font, four pixels per cell.
        // Index 255 on the last two top-row pixels trims each glyph from 4 to 2.
        let sheetWidth = 40, sheetHeight = 38
        let pitch = (sheetWidth + 3) & ~3
        var fontImage = [UInt8](repeating: 0, count: 54 + 256*4 + pitch*sheetHeight)
        fontImage[0] = 66; fontImage[1] = 77
        func setDword(_ position: Int, _ n: UInt32) {
            for i in 0..<4 { fontImage[position+i] = UInt8(truncatingIfNeeded: n >> (8*i)) }
        }
        setDword(2, UInt32(fontImage.count))
        setDword(10, 54+256*4)
        setDword(14, 40)
        setDword(18, UInt32(sheetWidth))
        setDword(22, UInt32(sheetHeight))
        fontImage[26] = 1
        fontImage[28] = 8
        setDword(34, UInt32(pitch*sheetHeight))
        for i in 0..<256 { let pos = 54+i*4; fontImage[pos] = UInt8(i); fontImage[pos+1] = UInt8(i); fontImage[pos+2] = UInt8(i) }
        let topRowStart = 54 + 256*4 + (sheetHeight-1)*pitch
        fontImage[topRowStart+2] = 255
        fontImage[topRowStart+3] = 255
        let font = try PalettedBMP(data: Data(fontImage))
        precondition(font.width == sheetWidth && font.height == sheetHeight)
        let widths = try font.originalFontWidths()
        precondition(widths[0] == 2)
        precondition(widths[1] == 4)
        precondition(font.rgba[3] == 0) // palette index zero transparent
        failure("truncated bitmap") { _ = try PalettedBMP(data: Data(fontImage.dropLast())) }
        failure("invalid font dimensions") {
            let simple = Data(fontImage.prefix(54))
            _ = try PalettedBMP(data: simple)
        }
        print("PASS: WAD0/WAD1 precedence, CFG menu definitions, mission order, terrain maps, original bitmap font widths")
    }
}
