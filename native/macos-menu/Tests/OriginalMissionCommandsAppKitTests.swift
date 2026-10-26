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
            precondition(ui.hitTest(NSPoint(x: 1, y: 1)) != nil, "Sidebar background must consume cave clicks")
            precondition(ui.hitTest(NSPoint(x: -2, y: -2)) == nil)
            ui.update(page: .raider, hasRaider: true, permitted: true)
            button("First-person view").performClick(nil)
            precondition(commands.last == "GotoFirstPerson")
            ui.update(page: .firstPerson, hasRaider: true, permitted: true)
            button("Overhead view").performClick(nil)
            precondition(commands.last == "GotoTopView")
        }
        button("Back").performClick(nil)
        precondition(backClicks == 1)
        print("AppKit mission command dispatch, tutorial lock, layout and hit tests passed")
    }
}
