import Foundation

/// Synthetic fixtures only. Standalone portable build:
/// swiftc Sources/LegoConfig.swift Sources/OriginalMissionBriefing.swift \
///   Tests/OriginalMissionBriefingTests.swift -o /tmp/openlrr-briefing-test
@main struct OriginalMissionBriefingTests {
    static func main() throws {
        try textSectionsAndEscapes()
        try malformedText()
        try configurationAndLayout()
        try configuredContinuePrompt()
        try keyboardLifecycle()
        try mouseLifecycle()
        try openingInputDrain()
        try malformedInput()
        clocksAndStartup()
        print("Original mission briefing text, geometry and input tests passed")
    }

    static func parse(_ text: String, level: String = "Levels::Level01") throws -> OriginalMissionBriefingText {
        try OriginalMissionBriefingText(data: Data(text.utf8), levelIdentifier: level)
    }

    static func invalid(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Malformed briefing input was accepted")
        } catch is OriginalMissionBriefingError {
            // Expected typed validation failure, not a silent fallback.
        } catch {
            preconditionFailure("Unexpected error: \(error)")
        }
    }

    static func textSectionsAndEscapes() throws {
        let text = try parse(#"""
        [Level010]
        Objective: Wrong mission
        [lEvEl01] trailing section comment
        Completion: Not the initial objective
        Failure: Also not the initial objective
        CrystalFailure: Nor this status
         Objective: A leading space does not match the original prefix
        oBJECTIVE: 	 Body_under\nNext\aLast\N\A\q
        [Other]
        Objective: Wrong mission again
        [bEgIn]
         Begin_under\n\a
        ignored second begin line
        """#)
        precondition(text.body == "Body_under \nNext \u{7}" + #"Last\N\A\q"#)
        precondition(text.pages == ["Body_under \nNext ", #"Last\N\A\q"#])
        precondition(text.beginText == #" Begin_under\n\a"#)
        let whitespace = try parse("[Level01]\nObjective: \t  literal_under\n")
        precondition(whitespace.body == "literal_under")
        let escapes = try parse(#"""
        [Level01]
        Objective: A\\nB\\aC\N\A\q\
        """#)
        precondition(escapes.body == "A\\ \nB\\ \u{7}C\\N\\A\\q\\")
        precondition(escapes.pages == ["A\\ \nB\\ ", "C\\N\\A\\q\\"])

        let emptyPages = try parse("[Level01]\nObjective: \\a\\a\n")
        precondition(emptyPages.pages == [" ", " ", ""], "Do not discard blank or trailing pages")
        let optional = try parse("")
        precondition(optional.body == nil && optional.pages == [""], "Absent optional ObjectiveText still has a blank initial page")
        let absent = try parse("[Level02]\nObjective: Other\n")
        precondition(absent.body == nil && absent.pages == [""] && !absent.hasBeginText)
        let empty = try parse("[Level01]\nObjective: \n")
        precondition(empty.body == "" && empty.pages == [""])
        let noBeginLine = try parse("[BEGIN]\n[Level01]\nObjective: Body\n")
        precondition(noBeginLine.beginText == nil, "A new section cancels pending BEGIN")
        let blankBegin = try parse("[BEGIN]\n\nnot begin\n[Level01]\nObjective: Body\n")
        precondition(blankBegin.beginText == "" && blankBegin.hasBeginText)
        let beginAtEOF = try parse("[BEGIN]\n")
        precondition(beginAtEOF.beginText == nil)
        let nonHeader = try parse(" [Level01]\nObjective: Not selected\n")
        precondition(nonHeader.body == nil)
        let crlf = try parse("[Level01]\r\nObjective: Last character kept!\r\n[BEGIN]\r\nBegin!")
        precondition(crlf.body == "Last character kept!" && crlf.beginText == "Begin!")
        let bodyAtEOF = try parse("[Level01]\nObjective: EOF!")
        precondition(bodyAtEOF.body == "EOF!")
        let special = try parse("[BEGIN]\nObjective: Both roles\n", level: "Levels::BEGIN")
        precondition(special.body == "Both roles" && special.beginText == "Objective: Both roles")
        let bytes = Data(Array("[Level01]\nObjective: Caf".utf8) + [0xe9, 10])
        let accented = try OriginalMissionBriefingText(data: bytes, levelIdentifier: "Levels::Level01")
        precondition(accented.body == "Café")
    }

    static func malformedText() throws {
        for level in ["Level01", "Levels::", "::Level01", "Other::Level01", "Levels::A::B",
                      "Levels::../Level01", "Levels::A[B]", "Levels::A\nB"] {
            invalid { _ = try parse("[Level01]\nObjective: Body\n", level: level) }
        }
        invalid { _ = try parse("[Level01]\nObjective: First\nObjective: Second\n") }
        invalid { _ = try parse("[Level01]\nObjective: First\n[LEVEL01]\nObjective: Second\n") }
        invalid { _ = try parse("[BEGIN]\nFirst\n[BEGIN]\nSecond\n") }
        for byte in [UInt8(0), 7, 13, 27] {
            invalid {
                _ = try OriginalMissionBriefingText(
                    data: Data(Array("[Level01]\nObjective: A".utf8) + [byte, 66, 10]),
                    levelIdentifier: "Levels::Level01")
            }
        }
        let limit = OriginalMissionBriefingText.maximumLineBytes
        let longest = "Objective:" + String(repeating: "x", count: limit - "Objective:".utf8.count)
        let longestText = try parse("[Level01]\n" + longest + "\r\n")
        precondition(longestText.body?.utf8.count == limit - 10)
        invalid { _ = try parse("[Level01]\n" + longest + "x\n") }
        invalid {
            _ = try OriginalMissionBriefingText(
                data: Data(repeating: 65, count: OriginalMissionBriefingText.maximumFileBytes + 1),
                levelIdentifier: "Levels::Level01")
        }
        // Lots of empty lines and separators remain bounded, without recursion.
        let manyLines = try parse(String(repeating: "\n", count: 20_000) + "[Level01]\nObjective: End\n")
        precondition(manyLines.body == "End")
        let manyPages = try parse("[Level01]\nObjective:" + String(repeating: "\\a", count: 500) + "\n")
        precondition(manyPages.pages.count == 501)
    }

    static func configurationAndLayout() throws {
        let config = try LegoConfig(text: #"""
        Lego* {
          Main {
            MissionBriefingText Mission_Briefing
            NextButton640x480 Interface\Next.bmp
            BackButton640x480 Interface\Back.bmp
            BackArrow Interface\PreviousArrow.bmp
            NextButtonPos640x480 999,999
            BackButtonPos640x480 888,888
          }
          Levels {
            Level01 {
              ObjectiveText Levels\Objective.txt
              ObjectiveImage640x480 Interface\Brief.bmp,10,-5
            }
          }
        }
        """#)
        let definition = try OriginalMissionBriefingDefinition(config: config, levelIdentifier: "levels::LEVEL01")
        precondition(definition.objectiveTextPath == "Levels/Objective.txt")
        precondition(definition.heading == "Mission Briefing")
        precondition(definition.headingBeforeUnderscoreReplacement == "Mission_Briefing")
        precondition(definition.panel?.path == "Interface/Brief.bmp")
        precondition(definition.panel?.position == CGPoint(x: 10, y: -5))
        precondition(definition.panel?.transparency == .paletteZero)
        precondition(definition.nextButtonPath == "Interface/Next.bmp")
        precondition(definition.previousHitTestPath == "Interface/Back.bmp")
        precondition(definition.previousArrowPath == "Interface/PreviousArrow.bmp")
        precondition(OriginalMissionBriefingDefinition.bodyFontPath == "Interface/Fonts/MBriefFONT.bmp")
        precondition(OriginalMissionBriefingDefinition.headingFontPath == "Interface/Fonts/MBriefFONT2.bmp")
        precondition(OriginalMissionBriefingDefinition.pageButtonTransparency == .rgb(0, 0, 0))
        let keyed = try OriginalMissionBriefingDefinition.Panel(setting: "Interface/P.bmp, 0, 20, 1, 128, 255")
        precondition(keyed.transparency == .rgb(1, 128, 255))
        let blank = try OriginalMissionBriefingDefinition(config: nil, levelIdentifier: "Levels::Level01")
        precondition(blank.speechSampleName == "Stream_Objective_Levels::Level01")
        precondition(blank.panel == nil && blank.objectiveTextPath == nil && blank.heading == nil)
        precondition(blank.nextButtonPath == nil && blank.previousHitTestPath == nil && blank.previousArrowPath == nil)

        let noBegin = try parse("[Level01]\nObjective: Body\n")
        let withBegin = try parse("[BEGIN]\n\n[Level01]\nObjective: Body\n")
        let expanded = OriginalMissionBriefingLayout(definition: definition, text: noBegin)
        let normal = OriginalMissionBriefingLayout(definition: definition, text: withBegin)
        precondition(expanded.body == CGRect(x: 70, y: 55, width: 390, height: 200))
        precondition(normal.body == CGRect(x: 70, y: 55, width: 390, height: 180))
        precondition(normal.begin == CGRect(x: 70, y: 215, width: 320, height: 20))
        precondition(normal.headingArea == CGRect(x: 50, y: 29, width: 422, height: 21))
        precondition(normal.headingFrame(measuredRawWidth: 201) == CGRect(x: 161, y: 29, width: 201, height: 21))
        precondition(OriginalMissionBriefingLayout.nextPosition == CGPoint(x: 470, y: 315))
        precondition(OriginalMissionBriefingLayout.previousPosition == CGPoint(x: 130, y: 315))
        precondition(!OriginalMissionBriefingLayout.bodyIsCentered)
        precondition(OriginalMissionBriefingLayout.beginIsCentered && OriginalMissionBriefingLayout.headingIsCentered)
        for width in [Double.nan, .infinity, -.infinity, -1, 1.5, 8193] {
            precondition(normal.headingFrame(measuredRawWidth: width) == nil)
        }
        for setting in ["", "P.bmp", "P.bmp,0", "P.bmp,0,0,1", "P.bmp,0,0,1,2",
                        "P.bmp,0,0,1,2,3,4", "P.bmp,nan,0", "P.bmp,0,inf", "P.bmp,0,1.5",
                        "P.bmp,8193,0", "P.bmp,0,-8193", "P.bmp,999999999999999999999999,0",
                        "P.bmp,0,0,-1,0,0", "P.bmp,0,0,0,256,0", "P.bmp,0,0,0,nan,0",
                        "../P.bmp,0,0", "/P.bmp,0,0", "C:\\P.bmp,0,0", "A//P.bmp,0,0",
                        "A/./P.bmp,0,0", "P\u{0}.bmp,0,0"] {
            invalid { _ = try OriginalMissionBriefingDefinition.Panel(setting: setting) }
        }
        let unsafe = try LegoConfig(text: "Lego* { Levels { Level01 { ObjectiveText ../outside.txt } } }")
        invalid { _ = try OriginalMissionBriefingDefinition(config: unsafe, levelIdentifier: "Levels::Level01") }
    }

    static func keyboardLifecycle() throws {
        var state = try OriginalMissionBriefingState(pageCount: 3)
        precondition(state.isShowing && state.pageIndex == 0 && state.hasNextPage && !state.hasPreviousPage)
        precondition(state.update(.init(spaceDown: true)) == .pageChanged(1))
        for _ in 0..<100 { precondition(state.update(.init(spaceDown: true)) == .none) }
        precondition(state.pageIndex == 1, "Held Space must not repeat")
        precondition(state.update(.init()) == .none)
        precondition(state.update(.init(spaceDown: true)) == .pageChanged(2))
        precondition(!state.hasNextPage && state.hasPreviousPage && state.isShowing)
        precondition(state.update(.init(spaceDown: true)) == .none)
        precondition(state.update(.init()) == .none)
        precondition(state.update(.init(spaceDown: true)) == .dismissed)
        precondition(!state.isActive && !state.isShowing && !state.hasPreviousPage)
        for _ in 0..<10 {
            precondition(state.update(.init()) == .none)
            precondition(state.update(.init(spaceDown: true)) == .none, "Dismissal is a one-shot effect")
        }
        var held = try OriginalMissionBriefingState(pageCount: 1, openingInput: .init(spaceDown: true))
        precondition(held.update(.init(spaceDown: true)) == .none)
        precondition(held.update(.init()) == .none)
        precondition(held.update(.init(spaceDown: true)) == .dismissed)
        var lostRelease = try OriginalMissionBriefingState(pageCount: 1)
        precondition(lostRelease.update(.init(leftDown: true)) == .none)
        lostRelease.synchronizeInput(.init())
        precondition(lostRelease.update(.init()) == .none && lostRelease.isShowing,
                     "Focus resynchronization must not act as a final-page click")
        lostRelease.synchronizeInput(.init(spaceDown: true))
        precondition(lostRelease.update(.init(spaceDown: true)) == .none)
        lostRelease.synchronizeInput(.init())
        precondition(lostRelease.update(.init(spaceDown: true)) == .dismissed)
    }

    static func click(_ point: CGPoint, state: inout OriginalMissionBriefingState) -> OriginalMissionBriefingState.Change {
        precondition(state.update(.init(leftDown: true, pointer: point)) == .none)
        return state.update(.init(pointer: point))
    }

    static func mouseLifecycle() throws {
        let size = CGSize(width: 20, height: 16)
        let next = CGPoint(x: 470, y: 315), previous = CGPoint(x: 130, y: 315)
        var state = try OriginalMissionBriefingState(pageCount: 3, nextButtonSize: size, previousHitTestSize: size)
        precondition(state.nextButtonFrame == CGRect(origin: next, size: size) && state.previousHitTestFrame == nil)
        precondition(click(CGPoint(x: 300, y: 200), state: &state) == .none)
        precondition(click(CGPoint(x: 490, y: 315), state: &state) == .none, "Right boundary is excluded")
        precondition(click(CGPoint(x: 470, y: 331), state: &state) == .none, "Bottom boundary is excluded")
        precondition(click(previous, state: &state) == .none)
        precondition(click(next, state: &state) == .pageChanged(1))
        precondition(state.previousHitTestFrame == CGRect(origin: previous, size: size))
        precondition(click(previous, state: &state) == .pageChanged(0))
        precondition(click(next, state: &state) == .pageChanged(1))
        // C++ checks Next before Previous for simultaneous input.
        precondition(state.update(.init(leftDown: true, pointer: previous)) == .none)
        precondition(state.update(.init(spaceDown: true, pointer: previous)) == .none)
        precondition(state.pageIndex == 1)
        precondition(state.update(.init()) == .none)
        precondition(click(next, state: &state) == .pageChanged(2))
        precondition(state.nextButtonFrame == nil)
        precondition(click(previous, state: &state) == .pageChanged(1), "Previous on last page is not dismissal")
        precondition(click(next, state: &state) == .pageChanged(2))
        precondition(state.update(.init(spaceDown: true, pointer: previous)) == .dismissed,
                     "Space dismisses even over Previous")

        var anywhere = try OriginalMissionBriefingState(pageCount: 1)
        precondition(click(previous, state: &anywhere) == .dismissed, "Hidden Previous is not a hit target")
        var missingArt = try OriginalMissionBriefingState(pageCount: 2)
        precondition(click(next, state: &missingArt) == .none, "Missing bitmap does not create an invisible control")
        precondition(missingArt.update(.init(spaceDown: true)) == .pageChanged(1))
        precondition(click(CGPoint(x: 12, y: 12), state: &missingArt) == .dismissed)
        var rightOnly = try OriginalMissionBriefingState(pageCount: 1)
        precondition(rightOnly.update(.init(rightDown: true, pointer: next)) == .none)
        precondition(rightOnly.update(.init(pointer: next)) == .none, "Right release is not a continue action")
    }

    static func openingInputDrain() throws {
        let point = CGPoint(x: 300, y: 200)
        for opening in [OriginalMissionBriefingInput(leftDown: true), .init(rightDown: true),
                        .init(leftHeld: true), .init(leftClicked: true)] {
            var state = try OriginalMissionBriefingState(pageCount: 1, openingInput: opening)
            precondition(state.phase == .drainingOpeningMouse && !state.isShowing && state.isActive)
            for _ in 0..<1000 { precondition(state.update(opening) == .none) }
            precondition(state.update(.init(pointer: point)) == .none, "Opening release must be drained")
            precondition(state.isShowing)
            precondition(state.update(.init(pointer: point)) == .none)
            precondition(click(point, state: &state) == .dismissed)
        }
        var simultaneous = try OriginalMissionBriefingState(pageCount: 2, openingInput: .init(leftDown: true))
        precondition(simultaneous.update(.init(spaceDown: true, leftDown: true)) == .none)
        precondition(simultaneous.update(.init(spaceDown: true)) == .none)
        precondition(simultaneous.update(.init(spaceDown: true)) == .none)
        precondition(simultaneous.pageIndex == 0)
        precondition(simultaneous.update(.init()) == .none)
        precondition(simultaneous.update(.init(spaceDown: true)) == .pageChanged(1))
    }

    static func malformedInput() throws {
        for count in [Int.min, -1, 0, OriginalMissionBriefingText.maximumPages + 1, Int.max] {
            invalid { _ = try OriginalMissionBriefingState(pageCount: count) }
        }
        for size in [CGSize.zero, CGSize(width: -1, height: 10), CGSize(width: 10, height: -1),
                     CGSize(width: CGFloat.nan, height: 10), CGSize(width: 10, height: CGFloat.infinity),
                     CGSize(width: 8193, height: 1)] {
            invalid { _ = try OriginalMissionBriefingState(pageCount: 1, nextButtonSize: size) }
            invalid { _ = try OriginalMissionBriefingState(pageCount: 1, previousHitTestSize: size) }
        }
        var state = try OriginalMissionBriefingState(pageCount: 1)
        let invalidPoints: [CGPoint?] = [nil, CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)]
        for point in invalidPoints {
            precondition(state.update(.init(leftDown: true, pointer: point)) == .none)
            precondition(state.update(.init(pointer: point)) == .none, "Invalid mouse coordinates do not dismiss")
        }
        precondition(state.update(.init(spaceDown: true, pointer: CGPoint(x: CGFloat.nan, y: 0))) == .dismissed,
                     "Invalid pointer does not disable valid keyboard input")
    }
    static func clocksAndStartup() {
        var clock = OriginalMissionClock()
        precondition(clock.advance(now: 10, paused: false) == 0)
        precondition(clock.advance(now: 10.5, paused: false) == 0.5)
        precondition(clock.advance(now: 20, paused: true) == 0)
        precondition(clock.advance(now: 30, paused: true) == 0)
        precondition(clock.advance(now: 100, paused: false) == 0, "No briefing catch-up on resume")
        precondition(clock.advance(now: 100.25, paused: false) == 0.25)
        clock.reset()
        precondition(clock.advance(now: 900, paused: false) == 0, "Detach/re-attach resets baseline")
        precondition(clock.advance(now: .nan, paused: false) == 0)
        precondition(clock.advance(now: 1000, paused: false) == 0)
        precondition(clock.advance(now: 999, paused: false) == 0, "Backward clock cannot reverse timers")

        var gate = OriginalMissionStartupGate()
        precondition(!gate.claimSpeechStart(briefingShowing: true))
        precondition(!gate.claimGameplayStart(briefingActive: false))
        gate.attach()
        precondition(!gate.claimSpeechStart(briefingShowing: false), "Drain opening input before speech")
        precondition(!gate.claimGameplayStart(briefingActive: true), "No music/cave ambience during briefing")
        precondition(gate.claimSpeechStart(briefingShowing: true))
        for _ in 0..<10 {
            gate.attach()
            precondition(!gate.claimSpeechStart(briefingShowing: true), "No replay on pages/attachment")
            precondition(!gate.claimGameplayStart(briefingActive: true))
        }
        precondition(gate.claimGameplayStart(briefingActive: false))
        precondition(!gate.claimGameplayStart(briefingActive: false), "One soundtrack/ambience handoff")
        gate.exit()
        gate.attach()
        precondition(!gate.isAttached && gate.hasExited)
        precondition(!gate.claimSpeechStart(briefingShowing: true))
        precondition(!gate.claimGameplayStart(briefingActive: false), "No stale callbacks after mission exit")
        var earlyExit = OriginalMissionStartupGate()
        earlyExit.attach(); earlyExit.exit()
        precondition(!earlyExit.claimSpeechStart(briefingShowing: true))
        precondition(!earlyExit.claimGameplayStart(briefingActive: false))
        var noBriefing = OriginalMissionStartupGate()
        noBriefing.attach()
        precondition(noBriefing.claimGameplayStart(briefingActive: false), "An explicitly briefing-free caller can start gameplay")
        precondition(!noBriefing.claimSpeechStart(briefingShowing: true))
    }

    static func configuredContinuePrompt() throws {
        let config = try LegoConfig(text: #"""
        Lego* {
          TextMessages { Text_SpaceToContinue Original_prompt\nContinue_under\N }
          Main { Text_SpaceToContinue Wrong_section }
        }
        """#)
        let definition = try OriginalMissionBriefingDefinition(config: config, levelIdentifier: "Levels::Level01")
        precondition(definition.continuePrompt == "Original prompt\nContinue under" + #"\N"#)
        precondition(!definition.continuePromptHasImage)
        precondition(definition.messageText(briefingActive: true, nerpsText: nil) == definition.continuePrompt,
                     "Frozen briefing still displays original configured Space prompt")
        precondition(definition.messageText(briefingActive: true, nerpsText: "NERP") == "NERP",
                     "Current NERP message retains the original precedence")
        precondition(definition.messageText(briefingActive: true, nerpsText: nil, messagePermit: false) == nil,
                     "SetMessagePermit(0) suppresses the generic prompt when no NERP text is active")
        precondition(definition.messageText(briefingActive: true, nerpsText: "NERP", messagePermit: false) == "NERP")
        precondition(definition.messageText(briefingActive: false, nerpsText: nil) == nil,
                     "Dismissal removes the prompt without clearing actual NERP messages")
        precondition(definition.messageText(briefingActive: false, nerpsText: "NERP") == "NERP")
        let missing = try OriginalMissionBriefingDefinition(config: nil, levelIdentifier: "Levels::Level01")
        precondition(missing.continuePrompt == nil && !missing.continuePromptHasImage)
        let override = try LegoConfig(text: """
        Lego* {
          TextMessages { Text_SpaceToContinue Plain }
          TextMessagesWithImages { Text_SpaceToContinue Image_prompt:Interface/Prompt.bmp:SFX_Name }
        }
        """)
        let image = try OriginalMissionBriefingDefinition(config: override, levelIdentifier: "Levels::Level01")
        precondition(image.continuePrompt == "Image prompt" && image.continuePromptHasImage,
                     "Image form overrides the text; unsupported image/SFX is diagnosed by the UI")
    }

}
