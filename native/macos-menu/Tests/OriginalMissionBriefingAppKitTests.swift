import AppKit

/// Synthetic WAD, palette, atlas and events only; no retail bytes or audio.
@main struct OriginalMissionBriefingAppKitTests {
    static func le(_ value: UInt32) -> [UInt8] {
        [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8),
         UInt8(truncatingIfNeeded: value >> 16), UInt8(truncatingIfNeeded: value >> 24)]
    }

    static func bitmap(width: Int, height: Int, pixel: (Int, Int) -> UInt8) -> [UInt8] {
        let pitch = (width + 3) & ~3
        let bytes = pitch * height
        let start = 54 + 256 * 4
        var bmp: [UInt8] = [66, 77] + le(UInt32(start + bytes)) + [0, 0, 0, 0] + le(UInt32(start))
        bmp += le(40) + le(UInt32(width)) + le(UInt32(height)) + [1, 0, 8, 0]
        bmp += le(0) + le(UInt32(bytes)) + le(0) + le(0) + le(256) + le(0)
        var palette = [UInt8](repeating: 0, count: 256 * 4)
        func color(_ index: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8) {
            palette[index * 4] = b; palette[index * 4 + 1] = g; palette[index * 4 + 2] = r
        }
        color(0, 0, 255, 0) // Nonblack palette-zero color.
        color(1, 0, 0, 0)
        color(2, 255, 255, 255)
        color(3, 0, 255, 0) // Duplicate RGB, different index.
        color(4, 0, 0, 255)
        color(5, 255, 0, 0)
        color(255, 255, 0, 255) // Synthetic glyph-width marker.
        bmp += palette
        for diskY in 0..<height {
            let y = height - diskY - 1
            for x in 0..<pitch { bmp.append(x < width ? pixel(x, y) : 0) }
        }
        return bmp
    }

    static func solid(_ width: Int, _ height: Int) -> [UInt8] {
        bitmap(width: width, height: height) { _, _ in 2 }
    }

    static func font(cellWidth: Int, cellHeight: Int, color: UInt8) -> [UInt8] {
        bitmap(width: cellWidth * 10, height: cellHeight * 19) { x, y in
            // Space is one pixel wide; underscore retains the full cell width.
            // The two widths intentionally differ to distinguish raw-title
            // frame placement from the replaced title's per-line centering.
            if y == 0 && x > 0 && x < cellWidth { return 255 }
            return color
        }
    }

    static func resources(_ entries: [(String, [UInt8])]) throws -> GameResources {
        let names = entries.flatMap { Array($0.0.utf8) + [UInt8(0)] }
        var offset = 8 + names.count * 2 + entries.count * 16
        var wad: [UInt8] = [87, 87, 65, 68] + le(UInt32(entries.count)) + names + names
        for (_, bytes) in entries {
            wad += le(1) + le(UInt32(bytes.count)) + le(UInt32(bytes.count)) + le(UInt32(offset))
            offset += bytes.count
        }
        for (_, bytes) in entries { wad += bytes }
        return try GameResources(archives: [(0, Data(wad))])
    }

    static func definition() throws -> OriginalMissionBriefingDefinition {
        let config = try LegoConfig(text: """
        Lego* {
            Main {
                MissionBriefingText A_A
                NextButton640x480 Next.bmp
                BackArrow BackArrow.bmp
                BackButton640x480 RepeatHit.bmp
            }
            Levels {
                Level01 {
                    ObjectiveText Briefing.txt
                    ObjectiveImage640x480 Panel.bmp,10,20
                }
            }
        }
        """)
        return try OriginalMissionBriefingDefinition(config: config, levelIdentifier: "Levels::Level01")
    }

    static func text(_ body: String = "A_A\\aSecond\\aLast") throws -> OriginalMissionBriefingText {
        try OriginalMissionBriefingText(data: Data("[Level01]\nObjective: \(body)\n[BEGIN]\nBEGIN_UNDER\n".utf8),
                                        levelIdentifier: "Levels::Level01")
    }

    static func main() throws {
        _ = NSApplication.shared
        let entries: [(String, [UInt8])] = [
            ("Panel.bmp", solid(500, 300)),
            ("Next.bmp", solid(24, 17)),
            ("BackArrow.bmp", solid(9, 7)),
            ("RepeatHit.bmp", solid(34, 21)),
            (OriginalMissionBriefingDefinition.bodyFontPath, font(cellWidth: 3, cellHeight: 5, color: 5)),
            (OriginalMissionBriefingDefinition.headingFontPath, font(cellWidth: 5, cellHeight: 7, color: 4))
        ]
        let assets = try resources(entries)
        try paletteTransparency(resources: assets)
        try fontsAndLayout(resources: assets)
        let sizes = [CGSize(width: 640, height: 480), CGSize(width: 1280, height: 960),
                     CGSize(width: 1600, height: 960), CGSize(width: 640, height: 960)]
        for size in sizes { try inputAndTransform(resources: assets, size: size) }
        try missingAssetsAndOpeningSpace(entries: entries)
        print("PASS: original mission briefing AppKit palette, fonts, transforms and input lifecycle")
    }

    static func paletteTransparency(resources: GameResources) throws {
        let decoded = try PalettedBMP(data: Data(bitmap(width: 4, height: 1) { x, _ in UInt8(x) }))
        func alpha(_ transparency: OriginalMissionBriefingDefinition.Transparency) -> [UInt8] {
            let rgba = OriginalMissionBriefingUI.rgba(decoded, transparency: transparency)
            return stride(from: 3, to: rgba.count, by: 4).map { rgba[$0] }
        }
        // Objective's default is the palette-zero COLOR, not RGB black and
        // not just index zero. Duplicate palette colors get the same key.
        precondition(alpha(.paletteZero) == [0, 255, 255, 0])
        precondition(alpha(.rgb(0, 0, 0)) == [255, 0, 255, 255])
        precondition(alpha(.rgb(255, 255, 255)) == [255, 255, 0, 255])
        precondition(OriginalMissionBriefingUI.image("Next.bmp", transparency: .rgb(0, 0, 0),
                                                    resources: resources)?.size == CGSize(width: 24, height: 17))
        precondition(OriginalMissionBriefingUI.image("BackArrow.bmp", transparency: .rgb(0, 0, 0),
                                                    resources: resources)?.size == CGSize(width: 9, height: 7))
        precondition(OriginalMissionBriefingUI.image("RepeatHit.bmp", transparency: .rgb(0, 0, 0),
                                                    resources: resources)?.size == CGSize(width: 34, height: 21))
    }

    static func fontsAndLayout(resources: GameResources) throws {
        let definition = try definition()
        let ui = try OriginalMissionBriefingUI(definition: definition, text: text(), resources: resources,
                                               openingInput: .init())
        precondition(ui.diagnostics.isEmpty, "Use both real atlas decoding paths, not system-font fallbacks")
        let body = OriginalBitmapFont.load(OriginalMissionBriefingDefinition.bodyFontPath, resources: resources)!
        let heading = OriginalBitmapFont.load(OriginalMissionBriefingDefinition.headingFontPath, resources: resources)!
        precondition(body.cellWidth == 3 && body.cellHeight == 5)
        precondition(heading.cellWidth == 5 && heading.cellHeight == 7)
        precondition(ui.bodyFontCellSize == CGSize(width: 3, height: 5))
        precondition(ui.headingFontCellSize == CGSize(width: 5, height: 7))
        precondition(body.layout("A_A")!.width == 9)
        precondition(heading.layout("A_A")!.width == 15 && heading.layout("A A")!.width == 11)
        precondition(ui.textLayout.body == CGRect(x: 70, y: 80, width: 390, height: 180))
        precondition(ui.textLayout.begin == CGRect(x: 70, y: 240, width: 320, height: 20))
        precondition(ui.textLayout.headingArea == CGRect(x: 50, y: 54, width: 422, height: 21))
        precondition(ui.textLayout.headingFrame(measuredRawWidth: 15) ==
                     CGRect(x: 254, y: 54, width: 15, height: 21), "Raw title uses integer width/2")
        precondition(ui.headingFrame == CGRect(x: 254, y: 54, width: 15, height: 21))
        precondition(definition.heading == "A A" && definition.headingBeforeUnderscoreReplacement == "A_A")
        precondition(ui.text.beginText == "BEGIN_UNDER")
        try rendersBothFonts(ui)
    }

    static func rendersBothFonts(_ ui: OriginalMissionBriefingUI) throws {
        ui.frame = CGRect(x: 0, y: 0, width: 640, height: 480)
        let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 480,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                      isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 640 * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pixels)!
        NSColor.clear.setFill()
        ui.bounds.fill()
        ui.draw(ui.bounds)
        // Actual draw path: body atlas is red and heading/BEGIN atlas blue.
        // This detects a swapped atlas or an unnoticed system-font fallback
        // without relying on display scale, screenshot files or retail pixels.
        let data = pixels.bitmapData!
        var red = 0, blue = 0
        for offset in stride(from: 0, to: pixels.bytesPerRow * pixels.pixelsHigh, by: 4) {
            if data[offset] > 200 && data[offset + 1] < 40 && data[offset + 2] < 40 { red += 1 }
            if data[offset] < 40 && data[offset + 1] < 40 && data[offset + 2] > 200 { blue += 1 }
        }
        precondition(red > 0 && blue > 0, "Original body and heading/BEGIN font pixels must both render")
    }

    static func inputAndTransform(resources: GameResources, size: CGSize) throws {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1800, height: 1200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        let ui = try OriginalMissionBriefingUI(definition: definition(), text: text(), resources: resources,
                                               openingInput: .init(leftDown: true))
        ui.frame = CGRect(origin: CGPoint(x: 23, y: 17), size: size)
        host.addSubview(ui)
        ui.layoutSubtreeIfNeeded()
        var dismissals = 0, exits = 0
        ui.onDismiss = { dismissals += 1 }
        ui.onExit = { exits += 1 }
        let expected = OriginalHUDTransform(size: size)
        precondition(ui.transform.scale == expected.scale && ui.transform.origin == expected.origin)
        func screen(_ logical: CGPoint) -> CGPoint {
            expected.screen(CGRect(origin: logical, size: .zero)).origin
        }
        func hit(_ logical: CGPoint) -> NSView? {
            ui.hitTest(ui.convert(screen(logical), to: host))
        }
        func mouse(_ type: NSEvent.EventType, _ logical: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: ui.convert(screen(logical), to: nil), modifierFlags: [],
                               timestamp: 0, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 1, clickCount: 1, pressure: 0)!
        }
        func key(_ type: NSEvent.EventType, code: UInt16 = 49, repeated: Bool = false,
                 modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                             timestamp: 0, windowNumber: window.windowNumber, context: nil,
                             characters: " ", charactersIgnoringModifiers: " ", isARepeat: repeated, keyCode: code)!
        }
        func click(_ logical: CGPoint) {
            precondition(ui.consume(mouse(.leftMouseDown, logical)))
            precondition(ui.consume(mouse(.leftMouseUp, logical)))
        }
        let outside = CGPoint(x: 300, y: 200)
        let next = CGPoint(x: 493.5, y: 331.5) // Inside the last Next pixel.
        let previous = CGPoint(x: 160, y: 333) // Inside RepeatHit, outside BackArrow.
        precondition(ui.isActive && !ui.objectiveShowing && ui.state.phase == .drainingOpeningMouse)
        precondition(hit(outside) === ui, "Even transparent overlay pixels block cave clicks")
        precondition(ui.consume(mouse(.leftMouseUp, outside)))
        precondition(ui.objectiveShowing && ui.state.pageIndex == 0 && dismissals == 0,
                     "Opening mission-icon release must not dismiss or advance")
        precondition(ui.state.nextButtonFrame == CGRect(x: 470, y: 315, width: 24, height: 17))
        precondition(ui.state.previousHitTestFrame == nil)
        click(outside)
        precondition(ui.state.pageIndex == 0)
        click(CGPoint(x: 494, y: 315))
        precondition(ui.state.pageIndex == 0, "Next's right boundary is excluded")
        click(previous)
        precondition(ui.state.pageIndex == 0, "Previous has no invisible first-page hit target")
        click(next)
        precondition(ui.state.pageIndex == 1)
        precondition(ui.state.previousHitTestFrame == CGRect(x: 130, y: 315, width: 34, height: 21))
        click(previous)
        precondition(ui.state.pageIndex == 0, "RepeatButtonImage dimensions, not BackArrow dimensions, control Previous")
        click(next)
        precondition(ui.consume(key(.keyDown)))
        precondition(ui.state.pageIndex == 2 && ui.state.nextButtonFrame == nil)
        for _ in 0..<5 { precondition(ui.consume(key(.keyDown, repeated: true))) }
        precondition(ui.isActive && ui.state.pageIndex == 2 && dismissals == 0)
        // Modifier changes must not leave the tracked Space key latched down.
        // App shortcuts pass through, but release state still needs clearing.
        precondition(!ui.consume(key(.keyUp, modifiers: [.command])))
        click(previous)
        precondition(ui.state.pageIndex == 1 && dismissals == 0, "Last-page Previous does not dismiss")
        precondition(ui.consume(key(.keyDown)))
        precondition(ui.state.pageIndex == 2, "Space must work after a Command-modified release")
        precondition(ui.consume(key(.keyUp)))
        precondition(ui.state.pageIndex == 2)
        precondition(ui.consume(key(.keyDown, code: 123)), "Camera keys are consumed")
        precondition(!ui.consume(key(.keyDown, code: 12, modifiers: [.command])), "App shortcuts remain available")
        precondition(ui.consume(key(.keyDown, code: 53)))
        precondition(exits == 1 && dismissals == 0 && ui.isActive, "Exit is not briefing dismissal")
        precondition(ui.consume(mouse(.rightMouseDown, outside)))
        precondition(ui.consume(mouse(.rightMouseUp, outside)))
        precondition(ui.isActive && dismissals == 0, "Right release does not continue")
        precondition(ui.consume(mouse(.leftMouseDown, outside)))
        precondition(ui.isActive)
        precondition(ui.consume(mouse(.leftMouseUp, outside)), "The closing release itself is consumed")
        precondition(!ui.isActive && !ui.objectiveShowing && ui.isHidden && dismissals == 1)
        precondition(hit(outside) == nil && ui.state.nextButtonFrame == nil && ui.state.previousHitTestFrame == nil)
        precondition(!ui.consume(mouse(.leftMouseUp, outside)))
        precondition(ui.apply(.init(spaceDown: true)) == .none && dismissals == 1)
        ui.removeFromSuperview()
    }

    static func missingAssetsAndOpeningSpace(entries: [(String, [UInt8])]) throws {
        let missing = try resources(entries.filter { $0.0 != "Next.bmp" && $0.0 != "RepeatHit.bmp" })
        let ui = try OriginalMissionBriefingUI(definition: definition(), text: text(), resources: missing,
                                               openingInput: .init(spaceDown: true))
        precondition(ui.objectiveShowing && ui.state.nextButtonFrame == nil)
        precondition(ui.diagnostics.contains { $0.contains("Next") })
        precondition(ui.diagnostics.contains { $0.contains("Previous") })
        precondition(ui.apply(.init(spaceDown: true)) == .none)
        precondition(ui.apply(.init()) == .none)
        precondition(ui.apply(.init(spaceDown: true)) == .pageChanged(1))
        precondition(ui.state.previousHitTestFrame == nil, "Missing hit art cannot create an invisible target")
        precondition(ui.apply(.init()) == .none)
        precondition(ui.apply(.init(leftDown: true, pointer: CGPoint(x: 470, y: 315))) == .none)
        precondition(ui.apply(.init(pointer: CGPoint(x: 470, y: 315))) == .none)
        precondition(ui.state.pageIndex == 1, "Missing Next art requires Space")
        var dismissals = 0
        ui.onDismiss = { dismissals += 1 }
        ui.cancel()
        precondition(!ui.isActive && !ui.objectiveShowing && ui.isHidden)
        precondition(ui.apply(.init(spaceDown: true)) == .none && dismissals == 0,
                     "Mission exit cancels without a dismissal/handoff callback")
    }
}
