import AppKit

@main struct OriginalMissionCommandsAppKitTests {
    static func main() throws {
        _ = NSApplication.shared
        let resources = try GameResources(archives: [(0, Data([87,87,65,68,0,0,0,0]))])
        let config = try LegoConfig(text: """
        Lego* {
            BuildingTypes {
                ToolStation Buildings/ToolStation
                TeleportPad Buildings/TeleportPad
            }
        }
        """)
        let ui = OriginalMissionCommands(resources: resources, config: config)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 1000))
        host.addSubview(ui)
        func hit(_ local: NSPoint) -> NSView? { ui.hitTest(ui.convert(local, to: host)) }
        func descendants(_ view: NSView) -> [NSView] {
            view.subviews.flatMap { [$0] + descendants($0) }
        }
        func button(_ title: String) -> NSButton {
            descendants(ui).compactMap { $0 as? NSButton }.first { $0.title == title }!
        }
        var commands: [String] = []
        var backClicks = 0
        ui.onCommand = { commands.append($0) }
        ui.onBack = { backClicks += 1 }
        for scale: CGFloat in [1, 2] {
            ui.logicalScale = scale
            ui.frame = NSRect(x: 0, y: 0, width: 90 * scale, height: 365 * scale)
            ui.update(page: .main, hasRaider: false, permitted: true)
            ui.layoutSubtreeIfNeeded()
            button("Buildings").performClick(nil)
            precondition(commands.last == "BuildBuilding")
            let count = commands.count
            button("Teleport Rock Raider").performClick(nil)
            precondition(commands.count == count, "Unavailable command must not dispatch")
            ui.update(page: .wall, hasRaider: true, permitted: false)
            button("Drill").performClick(nil)
            button("Back").performClick(nil)
            precondition(commands.count == count && backClicks == 0, "Tutorial icon lock")
            ui.update(page: .wall, hasRaider: true, permitted: true)
            ui.layoutSubtreeIfNeeded()
            button("Drill").performClick(nil)
            precondition(commands.last == "Dig")
            let scroll = ui.subviews.compactMap { $0 as? NSScrollView }.first!
            precondition(!scroll.frame.intersects(button("Back").frame), "Back must not cover scrolling icons")
            precondition(hit(NSPoint(x: 1, y: 1)) != nil, "Sidebar background must consume cave clicks")
            precondition(hit(NSPoint(x: -2, y: -2)) == nil)
            precondition(hit(NSPoint(x: 1, y: ui.bounds.height - 1)) == nil, "Unused sidebar area must leave cave input available")
            ui.update(page: .raider, hasRaider: true, permitted: true)
            button("First-person view").performClick(nil)
            precondition(commands.last == "GotoFirstPerson")
            ui.update(page: .firstPerson, hasRaider: true, permitted: true)
            button("Overhead view").performClick(nil)
            precondition(commands.last == "GotoTopView")
        }
        button("Back").performClick(nil)
        precondition(backClicks == 1)
        let messages = OriginalMissionMessageUI(resources: resources, config: config)
        messages.update(text: nil, canAdvance: false, hideArrow: false)
        precondition(!messages.isHidden, "Retail message panel remains visible without a message")
        precondition(messages.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.isHidden })
        // A synthetic indexed BMP checks real asset alpha hit testing without
        // putting retail artwork in the repository or CI artifacts.
        func le(_ n: UInt32) -> [UInt8] { [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)] }
        var bmp: [UInt8] = [66,77] + le(70) + [0,0,0,0] + le(62)
        bmp += le(40) + le(2) + le(2) + [1,0,8,0]
        bmp += le(0) + le(8) + le(0) + le(0) + le(2) + le(0)
        bmp += [0,0,0,0, 255,255,255,0]
        bmp += [1,1,0,0, 0,1,0,0] // bottom-up: transparent top-left.
        let name = Array("Panel.bmp".utf8) + [UInt8(0)]
        let offset = 8 + name.count * 2 + 16
        var wad = [UInt8]([87,87,65,68]) + le(1) + name + name
        wad += le(1) + le(UInt32(bmp.count)) + le(UInt32(bmp.count)) + le(UInt32(offset)) + bmp
        let imageResources = try GameResources(archives: [(0, Data(wad))])
        let imageConfig = try LegoConfig(text: "Lego* { Panels640x480 { Panel_TopPanel Panel.bmp,10,20,10,20 } }")
        let imagePanels = OriginalMissionPanels(resources: imageResources, config: imageConfig)
        host.addSubview(imagePanels)
        imagePanels.frame = NSRect(x: 0, y: 0, width: 640, height: 480)
        func panelHit(_ point: NSPoint) -> NSView? { imagePanels.hitTest(imagePanels.convert(point, to: host)) }
        precondition(panelHit(NSPoint(x: 10.25, y: 20.25)) == nil, "Black keyed artwork must pass cave input through")
        precondition(panelHit(NSPoint(x: 11.25, y: 20.25)) === imagePanels, "Visible panel pixels consume input")
        precondition(panelHit(NSPoint(x: 300, y: 200)) == nil, "Panel overlay must not cover the cave")
        imagePanels.frame.size = NSSize(width: 1280, height: 960)
        precondition(panelHit(NSPoint(x: 22.5, y: 40.5)) === imagePanels, "Scaled drawing and input must agree")
        print("AppKit mission command dispatch, tutorial lock, layout and hit tests passed")
    }
}
