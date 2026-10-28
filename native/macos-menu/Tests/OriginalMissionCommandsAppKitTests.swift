import AppKit

@main struct OriginalMissionCommandsAppKitTests {
    // Every byte is synthetic. No retail artwork is needed on the CI runner.
    static func le(_ n: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
         UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
    }
    static func bitmap(width: Int, height: Int) -> [UInt8] {
        let pitch = (width + 3) & ~3
        let bytes = pitch * height
        var bmp: [UInt8] = [66, 77] + le(UInt32(66 + bytes)) + [0, 0, 0, 0] + le(66)
        bmp += le(40) + le(UInt32(width)) + le(UInt32(height)) + [1, 0, 8, 0]
        bmp += le(0) + le(UInt32(bytes)) + le(0) + le(0) + le(3) + le(0)
        // Index zero is GREEN, index one is BLACK: hit testing must use the
        // RGB black key, not assume that palette index zero is transparent.
        bmp += [0, 255, 0, 0, 0, 0, 0, 0, 255, 255, 255, 0]
        for row in 0..<height {
            var pixels = [UInt8](repeating: 2, count: pitch)
            if row == height - 1 { pixels[0] = 1; if width > 1 { pixels[1] = 0 } }
            bmp += pixels
        }
        return bmp
    }
    static func resources(_ entries: [(String, [UInt8])]) throws -> GameResources {
        let names = entries.flatMap { Array($0.0.utf8) + [UInt8(0)] }
        var offset = 8 + names.count * 2 + entries.count * 16
        var wad: [UInt8] = [87, 87, 65, 68] + le(UInt32(entries.count)) + names + names
        for (_, data) in entries {
            wad += le(1) + le(UInt32(data.count)) + le(UInt32(data.count)) + le(UInt32(offset))
            offset += data.count
        }
        for (_, data) in entries { wad += data }
        return try GameResources(archives: [(0, Data(wad))])
    }
    static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
    static func button(_ title: String, in view: NSView) -> NSButton {
        descendants(view).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == title }!
    }
    static func main() throws {
        _ = NSApplication.shared
        let sizes = [CGSize(width: 40, height: 13), CGSize(width: 44, height: 27),
                     CGSize(width: 81, height: 150), CGSize(width: 67, height: 19)]
        var entries: [(String, [UInt8])] = [
            ("BackPanel.bmp", bitmap(width: 90, height: 260)),
            ("MainPanel.bmp", bitmap(width: 90, height: 260)),
            ("FirstPerson.bmp", bitmap(width: 83, height: 51)),
            ("BackHL.bmp", bitmap(width: 40, height: 20)),
            ("BackPR.bmp", bitmap(width: 40, height: 20)),
            ("Overhead.bmp", bitmap(width: 41, height: 31)),
            ("Panel.bmp", bitmap(width: 2, height: 2))
        ]
        for (index, size) in sizes.enumerated() {
            entries.append(("Icon\(index).bmp", bitmap(width: Int(size.width), height: Int(size.height))))
        }
        let imageResources = try resources(entries)
        let iconNames = [["TeleportMan", "BuildBuilding", "BuildSmallVehicle", "BuildLargeVehicle"],
                         ["Dig", "DeselectDig", "Reinforce", "Dynamite"],
                         ["GotoFirstPerson", "GetTool", "TrainSkill", "UpgradeMan"]]
        let iconConfig = iconNames.flatMap { names in
            names.enumerated().map { "Interface_MenuItem_\($0.element) Icon\($0.offset).bmp" }
        }.joined(separator: "\n")
        let config = try LegoConfig(text: """
        Lego* {
            BuildingTypes {
                ToolStation Buildings/ToolStation
                TeleportPad Buildings/TeleportPad
            }
            InterfaceImages {
                \(iconConfig)
                Interface_MenuItem_GotoTopView Overhead.bmp
            }
            InterfaceBackButton 40:20:BackHL.bmp:BackPR.bmp:Go_Back
            InterfaceSurroundImages {
                4 BackPanel.bmp:-24:-8:-31:233:MainPanel.bmp:-19:7
                1 BackPanel.bmp:-24:-8:-31:233:FirstPerson.bmp:-12:-4
                2 Broken.bmp:nan:22:8:240
            }
            Panels640x480 { Panel_TopPanel Panel.bmp,10,20,10,20 }
        }
        """)
        let ui = OriginalMissionCommands(resources: imageResources, config: config)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 1800, height: 1200))
        host.addSubview(ui)
        var commands: [String] = []
        var backClicks = 0
        ui.onCommand = { commands.append($0) }
        ui.onBack = { backClicks += 1 }
        let viewSizes = [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 960),
                         CGSize(width: 1600, height: 960), CGSize(width: 640, height: 960)]
        for size in viewSizes {
            // Nonzero frame origin also exercises flipped host conversion.
            ui.frame = NSRect(origin: CGPoint(x: 23, y: 17), size: size)
            let transform = OriginalHUDTransform(size: size)
            func hit(_ logical: CGPoint) -> NSView? {
                let local = transform.screen(CGRect(origin: logical, size: .zero)).origin
                return ui.hitTest(ui.convert(local, to: host))
            }
            func update(_ page: OriginalMissionCommandCatalog.Page, raider: Bool = true, permitted: Bool = true) {
                ui.update(page: page, hasRaider: raider, permitted: permitted)
                ui.layoutSubtreeIfNeeded()
            }
            func checkArt(at origin: CGPoint) {
                precondition(hit(CGPoint(x: origin.x + 0.25, y: origin.y + 0.25)) == nil,
                             "Black keyed surround pixels must pass cave input through")
                precondition(hit(CGPoint(x: origin.x + 1.25, y: origin.y + 0.25)) === ui,
                             "Nonblack surround pixels (even palette zero) must consume input")
                precondition(hit(CGPoint(x: origin.x - 0.25, y: origin.y + 0.25)) == nil,
                             "Surround hit mask must not clamp or extend the configured art")
                precondition(hit(CGPoint(x: 300, y: 200)) == nil)
                precondition(hit(CGPoint(x: 570, y: 350)) == nil, "Unused sidebar is still cave")
            }
            update(.main, raider: false)
            let back = button("Back to main commands", in: ui)
            precondition(back.isHidden, "Main menu has no Back")
            let initialBackClicks = backClicks
            back.performClick(nil)
            precondition(backClicks == initialBackClicks)
            let titles = ["Teleport Rock Raider", "Buildings", "Small vehicles", "Large vehicles"]
            var y: CGFloat = 18
            for (title, iconSize) in zip(titles, sizes) {
                let icon = button(title, in: ui)
                precondition(icon.image != nil, "Exercise decoded original-art path, not fallback")
                precondition(icon.superview === ui, "Original icons must not be clipped by a narrow scroll view")
                precondition(icon.frame == transform.screen(CGRect(x: 565, y: y, width: iconSize.width, height: iconSize.height)))
                // Original icon hit boxes are rectangular, even on black pixels.
                precondition(hit(CGPoint(x: 565.25, y: y + 0.25)) === icon)
                y += iconSize.height
            }
            checkArt(at: CGPoint(x: 546, y: 25))
            button("Buildings", in: ui).performClick(nil)
            precondition(commands.last == "BuildBuilding")
            var count = commands.count
            button("Teleport Rock Raider", in: ui).performClick(nil)
            precondition(commands.count == count, "Unavailable gameplay stays disabled")

            update(.wall, permitted: false)
            let drill = button("Drill", in: ui)
            precondition(!drill.isEnabled && !back.isEnabled)
            precondition(back.frame == transform.screen(CGRect(x: 534, y: 251, width: 40, height: 20)),
                         "Back has an independent, possibly negative offset from the menu origin")
            precondition(hit(CGPoint(x: 534.25, y: 251.25)) === back)
            precondition(hit(CGPoint(x: 565.25, y: 18.25)) === drill, "Locked controls must not leak cave clicks")
            drill.performClick(nil)
            back.performClick(nil)
            precondition(commands.count == count && backClicks == initialBackClicks, "Tutorial icon lock")
            checkArt(at: CGPoint(x: 541, y: 10))
            update(.wall)
            drill.performClick(nil)
            precondition(commands.last == "Dig")
            back.performClick(nil)
            precondition(backClicks == initialBackClicks + 1)
            update(.wall, raider: false)
            count = commands.count
            button("Drill", in: ui).performClick(nil)
            precondition(commands.count == count, "No selected Raider cannot drill")
            update(.main, raider: false)
            drill.performClick(nil)
            precondition(commands.count == count, "Detached buttons cannot dispatch a new page's command")

            update(.raider)
            button("First-person view", in: ui).performClick(nil)
            precondition(commands.last == "GotoFirstPerson")
            update(.firstPerson)
            precondition(back.isHidden, "First person also uses the no-Back surround")
            let overhead = button("Overhead view", in: ui)
            precondition(overhead.frame == transform.screen(CGRect(x: 565, y: 18, width: 41, height: 31)))
            checkArt(at: CGPoint(x: 553, y: 14))
            count = backClicks
            back.performClick(nil)
            precondition(backClicks == count)
            overhead.performClick(nil)
            precondition(commands.last == "GotoTopView")
            update(.firstPerson, permitted: false)
            count = commands.count
            overhead.performClick(nil)
            precondition(commands.count == count)

            // A malformed surround changes to readable native fallback, then
            // returns to original art without stale geometry or opaque cave UI.
            update(.buildings)
            precondition(!back.isHidden)
            let scroll = ui.subviews.compactMap { $0 as? NSScrollView }.first!
            precondition(!scroll.isHidden && !scroll.frame.intersects(back.frame))
            precondition(hit(CGPoint(x: 566, y: 19)) != nil)
            precondition(hit(CGPoint(x: 300, y: 200)) == nil)
            update(.main)
            precondition(scroll.isHidden)
            checkArt(at: CGPoint(x: 546, y: 25))
            ui.isHidden = true
            precondition(hit(CGPoint(x: 566, y: 19)) == nil)
            ui.isHidden = false
            if size.height > size.width {
                precondition(ui.hitTest(ui.convert(CGPoint(x: 566, y: 19), to: host)) == nil,
                             "Tall-window letterbox must not retain the old command hit region")
            }
        }

        // A missing highlight overlay must not inflate Back's configured hit
        // box when its original surround and coordinates are still available.
        let partialConfig = try LegoConfig(text: """
        Lego* {
            InterfaceBackButton 40:20:MissingBackHL.bmp:BackPR.bmp:Go_Back
            InterfaceSurroundImages {
                4 BackPanel.bmp:-24:-8:-31:233:MainPanel.bmp:-19:7
            }
        }
        """)
        let partial = OriginalMissionCommands(resources: imageResources, config: partialConfig)
        host.addSubview(partial)
        for size in viewSizes {
            partial.frame = NSRect(origin: .zero, size: size)
            partial.update(page: .wall, hasRaider: true, permitted: true)
            partial.layoutSubtreeIfNeeded()
            let transform = OriginalHUDTransform(size: size)
            let back = button("Back to main commands", in: partial)
            precondition(back.frame == transform.screen(CGRect(x: 534, y: 251, width: 40, height: 20)))
            let outside = transform.screen(CGRect(x: 535, y: 272, width: 0, height: 0)).origin
            precondition(partial.hitTest(partial.convert(outside, to: host)) == nil,
                         "Missing Back highlight cannot create an oversized cave input blocker")
        }

        // Missing files (distinct from malformed CFG) retain the scrollable
        // fallback; changing pages resets its scroll position.
        let buildingRows = (0..<15).map { "Building\($0) Buildings/\($0)" }.joined(separator: "\n")
        let fallbackConfig = try LegoConfig(text: """
        Lego* {
            BuildingTypes { \(buildingRows) }
            InterfaceSurroundImages { 4 Missing.bmp:-24:-8:-31:233:AlsoMissing.bmp:-19:7 }
        }
        """)
        let fallback = OriginalMissionCommands(resources: imageResources, config: fallbackConfig)
        host.addSubview(fallback)
        for size in viewSizes {
            fallback.frame = NSRect(origin: .zero, size: size)
            fallback.update(page: .buildings, hasRaider: false, permitted: true)
            fallback.layoutSubtreeIfNeeded()
            let scroll = fallback.subviews.compactMap { $0 as? NSScrollView }.first!
            let back = button("Back to main commands", in: fallback)
            precondition(!scroll.isHidden && !scroll.frame.intersects(back.frame))
            precondition(scroll.documentView!.frame.height > scroll.contentSize.height)
            precondition(back.frame.maxY <= OriginalHUDTransform(size: size).screen(CGRect(x: 565, y: 390, width: 75, height: 1)).maxY)
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 40))
            fallback.update(page: .main, hasRaider: false, permitted: true)
            fallback.layoutSubtreeIfNeeded()
            precondition(scroll.contentView.bounds.origin == .zero)
            precondition(back.isHidden)
            precondition(button("Buildings", in: fallback).image == nil)
        }

        let messages = OriginalMissionMessageUI(resources: imageResources, config: config)
        messages.update(text: nil, canAdvance: false, hideArrow: false)
        precondition(!messages.isHidden, "Retail message panel remains visible without a message")
        precondition(messages.subviews.compactMap { $0 as? NSButton }.allSatisfy { $0.isHidden })
        let panels = OriginalMissionPanels(resources: imageResources, config: config)
        host.addSubview(panels)
        for size in viewSizes {
            panels.frame = NSRect(origin: .zero, size: size)
            let transform = OriginalHUDTransform(size: size)
            func panelHit(_ logical: CGPoint) -> NSView? {
                let point = transform.screen(CGRect(origin: logical, size: .zero)).origin
                return panels.hitTest(panels.convert(point, to: host))
            }
            precondition(panelHit(CGPoint(x: 10.25, y: 20.25)) == nil)
            precondition(panelHit(CGPoint(x: 11.25, y: 20.25)) === panels)
            precondition(panelHit(CGPoint(x: 300, y: 200)) == nil)
        }
        print("AppKit original command art, geometry, transitions, locks, fallback and alpha hit tests passed")
    }
}
