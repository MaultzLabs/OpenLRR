import Foundation

private func encode(_ operations: [(UInt16, UInt16)]) throws -> NERPsScript {
    var bytes: [UInt8] = []
    for (opcode, operand) in operations {
        bytes += [UInt8(truncatingIfNeeded: operand),
                  UInt8(truncatingIfNeeded: operand >> 8),
                  UInt8(truncatingIfNeeded: opcode),
                  UInt8(truncatingIfNeeded: opcode >> 8)]
    }
    return try NERPsScript(data: Data(bytes))
}

@main struct NativeNERPsGameStateTests {
    static func main() throws {
        try initialBriefingBridge()
        try openingBriefingDoesNotBypassScript()
        // Retail uses function opcodes for True/False/Null, not literals.
        let startup = NativeNERPsGameState(script: try encode([
            (2, 1), (2, 0x19), (0, 7),
            (2, 2), (2, 0x19), (0, 99),
            (2, 3), (2, 0x19), (0, 98),
            (2, 1), (2, 0x1a), (2, 1),
            (2, 1), (2, 0)
        ]))
        let startupTick = try startup.tick(elapsedMilliseconds: 0)
        precondition(startup.registers[0] == 7 && startup.registers[1] == 1)
        precondition(startupTick.actionsExecuted == 2 && startupTick.stoppedByStopFunction)
        let random = startup.functions()
        // Source LCG seeded with 1 produces 41,18467,6334,26500.
        precondition(random[4]!.invoke([]) == 41)
        precondition(random[5]!.invoke([]) == 7)
        precondition(random[6]!.invoke([]) == 34)
        precondition(random[7]!.invoke([]) == 0)
        let unknownArgument = NativeNERPsGameState(script: try encode([
            (2, 1), (2, 0x19), (2, 90)
        ]))
        do {
            _ = try unknownArgument.tick(elapsedMilliseconds: 0)
            preconditionFailure("Unknown nested function became a packed integer")
        } catch NERPsRuntime.RuntimeError.missingSignature(let pc, let id) {
            precondition(pc == 2 && id == 90)
        }
        let voiceFile = try NativeNERPsMessageFile(data: Data((
            "$intro\tSounds\\Streamed\\Chief_intro\r\n" +
            "$bad ../escape\n" +
            "Welcome_Raider!#INTRO#\nNo_sound.\nAgain#intro#\n"
        ).utf8))
        precondition(voiceFile.lines.count == 3)
        precondition(voiceFile.text(for: 1) == "Welcome Raider!")
        precondition(voiceFile.soundPaths(for: 0) == ["Sounds/Streamed/Chief_intro.wav"])
        precondition(voiceFile.soundPaths(for: -1).isEmpty)
        let voiced = NativeNERPsGameState(script: try encode([]), messages: voiceFile)
        var sounds: [String] = []
        voiced.playMessageSound = { sounds.append($0); return 2.25 }
        let voice = voiced.functions()
        _ = voice[0x31]!.invoke([0])
        _ = voice[0x10]!.invoke([1, 1])
        precondition(sounds.count == 1 && voiced.messageTimer == 2750)
        try voiced.advanceTimers(milliseconds: 250)
        _ = voice[0x10]!.invoke([0, 1])
        precondition(sounds.count == 1 && voiced.messageTimer == 2500, "0 and 1 identify the same line")
        _ = voice[0x10]!.invoke([2, 1])
        precondition(voiced.messageTimer == 4000, "Original no-sample delay")
        _ = voice[0x10]!.invoke([3, 1])
        precondition(sounds.count == 1, "Do not restart the same sound for another line")
        try voiced.advanceTimers(milliseconds: 4000)
        precondition(voice[0x6b]!.invoke([]) == 0)

        let state = NativeNERPsGameState(script: try encode([
            (0, 1), (2, 0x19), (0, 7),    // SetR0(7), guarded by true
            (2, 0x11), (1, 5), (0, 6),    // GetR0 > 6
            (2, 0x22), (0, 4)             // AddR1(4)
        ]))
        var recorded: [Int] = []
        let first = try state.tick(elapsedMilliseconds: 33.0,
                                    onCall: { recorded.append($0.functionID) })
        precondition(first.actionsExecuted == 2)
        precondition(state.registers[0] == 7 && state.registers[1] == 4)
        precondition(recorded.contains(0x19) && recorded.contains(0x11)
                     && recorded.contains(0x22))
        _ = try state.tick(elapsedMilliseconds: 17.0)
        precondition(state.registers[1] == 8, "Registers must persist between ticks")
        precondition(state.completedTicks == 2)
        precondition(state.timers[0] == 50.0)

        state.isPaused = true
        let pausedTimers = state.timers
        let pausedRegisters = state.registers
        let pausedTick = try state.tick(elapsedMilliseconds: 10000)
        precondition(pausedTick.functionCalls == 0)
        precondition(state.timers == pausedTimers && state.registers == pausedRegisters)
        precondition(state.completedTicks == 2)
        state.isPaused = false
        _ = try state.tick(elapsedMilliseconds: 0)
        precondition(state.registers[1] == 12)
        precondition(state.timers == pausedTimers)

        // The original OpenLRR functions use signed 32-bit registers.
        let callbacks = state.functions()
        state.reportDigIconClick()
        state.reportDigIconClick()
        state.reportBackIconClick()
        state.reportBuildIconClick()
        precondition(callbacks[0x35]!.invoke([]) == 1)
        precondition(callbacks[0x35]!.invoke([]) == 1)
        _ = callbacks[0x36]!.invoke([0])
        precondition(callbacks[0x35]!.invoke([]) == 0)
        precondition(callbacks[0x41]!.invoke([]) == 2)
        precondition(callbacks[0x41]!.invoke([]) == 2, "Query must not consume clicks")
        precondition(callbacks[0x3e]!.invoke([]) == 1)
        _ = callbacks[0x40]!.invoke([0])
        precondition(callbacks[0x41]!.invoke([]) == 0)
        precondition(callbacks[0x3e]!.invoke([]) == 1, "Separate icon counters")
        _ = callbacks[0x3d]!.invoke([7])
        precondition(callbacks[0x3e]!.invoke([]) == 7)
        _ = callbacks[0x19]!.invoke([Int32.max])
        precondition(callbacks[0x11]!.invoke([]) == Int32.max)
        _ = callbacks[0x21]!.invoke([1])
        precondition(callbacks[0x11]!.invoke([]) == Int32.min)
        _ = callbacks[0x29]!.invoke([1])
        precondition(callbacks[0x11]!.invoke([]) == Int32.max)

        // SetTimer uses UInt32(bitPattern: value) and returns 1 in C++.
        precondition(callbacks[0x47]!.invoke([900]) == 1)
        try state.advanceTimers(milliseconds: 125.5)
        precondition(callbacks[0x43]!.invoke([]) == 1025)
        precondition(state.timers[0] == 1025.5)

        // Direct native UI/gameplay tutorial flags, not a no-op callback.
        precondition(callbacks[0x5e]!.invoke([7]) == 7)
        precondition(callbacks[0x5d]!.invoke([]) == 7)
        precondition(state.tutorialFlags == 7)

        let before = state.timers
        do {
            try state.advanceTimers(milliseconds: -.infinity)
            preconditionFailure("Non-finite elapsed time accepted")
        } catch NativeNERPsGameState.StateError.invalidElapsedTime {
            precondition(state.timers == before)
        }

        // Unsupported retail calls are reported, never fabricated.
        let unknown = NativeNERPsGameState(script: try encode([
            (0, 1), (2, 90)
        ]))
        do {
            _ = try unknown.tick(elapsedMilliseconds: 15)
            preconditionFailure("Unimplemented function was ignored")
        } catch NERPsRuntime.RuntimeError.missingSignature(_, let id) {
            precondition(id == 90)
            precondition(unknown.completedTicks == 0)
        }

        // Original tutorial messaging: a synthetic NPL first enables
        // messages, then displays the first synthetic message-file line.
        let messages = try NativeNERPsMessageFile(data: Data(
            ":picture World\\Tutorial.bmp\r\n$voice Sounds\\Chief\r\nHello_Raider! <picture> #voice#\r\nSecond_message\n".utf8))
        precondition(messages.lines.count == 2)
        precondition(messages.text(for: 0)?.hasPrefix("Hello Raider!") == true)
        precondition(messages.text(for: 1) == messages.text(for: 0))
        precondition(messages.text(for: 2) == "Second message")
        precondition(messages.text(for: 3) == nil)
        let tutorial = NativeNERPsGameState(script: try encode([
            (0, 1), (2, 0x31), (0, 0),        // TRUE ? SetMessagePermit 0
            (0, 1), (2, 0x10), (0, 1), (0, 1) // TRUE ? SetMessage 1 1
        ]), messages: messages)
        precondition(tutorial.messagePermit)
        let messageTick = try tutorial.tick(elapsedMilliseconds: 40)
        precondition(messageTick.actionsExecuted == 2)
        precondition(!tutorial.messagePermit)
        precondition(tutorial.lastMessageNumber == 1)
        precondition(tutorial.messageText?.hasPrefix("Hello Raider!") == true)
        precondition(tutorial.nextArrowDisabled)
        let tutorialCallbacks = tutorial.functions()
        precondition(tutorialCallbacks[0x31]!.invoke([1]) == 1)
        precondition(tutorial.messageText == nil && tutorial.messagePermit)
        precondition(tutorialCallbacks[0x10]!.invoke([2, 0]) == 0)
        precondition(tutorial.messageText == nil, "Blocked message must stay hidden")
        precondition(tutorialCallbacks[0x31]!.invoke([0]) == 0)
        precondition(tutorialCallbacks[0x10]!.invoke([2, 0]) == 0)
        precondition(tutorial.messageText == "Second message")
        precondition(!tutorial.nextArrowDisabled)
        precondition(tutorialCallbacks[0x10]!.invoke([-1, 0]) == 0)
        precondition(tutorial.messageText == nil, "Invalid line cannot display text")
        do {
            _ = try NativeNERPsMessageFile(data: Data(repeating: 65, count: 1_000_001))
            preconditionFailure("Oversized NERP message file accepted")
        } catch NativeNERPsMessageFile.MessageError.oversized {}

        // Original NERPs objective-switch functions (BF/C0) are a one-shot
        // latch, NOT a persistent objective-visible boolean. A second read
        // must return false even when the set value was greater than one.
        precondition(callbacks[0xc0]!.invoke([]) == 0)
        precondition(callbacks[0xbf]!.invoke([7]) == 7)
        precondition(state.objectiveSwitch == 7)
        precondition(callbacks[0xc0]!.invoke([]) == 1)
        precondition(state.objectiveSwitch == 0)
        precondition(callbacks[0xc0]!.invoke([]) == 0)
        precondition(callbacks[0xbf]!.invoke([0]) == 0)
        precondition(callbacks[0xc0]!.invoke([]) == 0)

        // Exercise the real interpreter: a true switch sets R0; the
        // second GetObjectiveSwitch is false, so SetR1 is suppressed.
        let objective = NativeNERPsGameState(script: try encode([
            (0, 1), (2, 0xbf), (0, 1),
            (2, 0xc0), (2, 0x19), (0, 1),
            (2, 0xc0), (2, 0x1a), (0, 1)
        ]))
        let objectiveTick = try objective.tick(elapsedMilliseconds: 16)
        precondition(objectiveTick.actionsExecuted == 2)
        precondition(objective.registers[0] == 1)
        precondition(objective.registers[1] == 0)
        precondition(objective.objectiveSwitch == 0)

        // Retail NPL message-control opcodes now have working callbacks.
        // They must acknowledge each message ONCE, even if the same SetMessage
        // runs on every frame, and must respect the message-file line count.
        let guide = try NativeNERPsMessageFile(
            data: Data("Welcome_Raider!\nSelect_the_rock.\n".utf8))
        let guideState = NativeNERPsGameState(script: try encode([]),
                                              messages: guide)
        let guideFunctions = guideState.functions()
        precondition(guideFunctions[0x58]?.kind.arity == 1)
        precondition(guideFunctions[0x6b]?.kind.arity == 0)
        precondition(guideFunctions[0x6c]?.kind.arity == 3)
        precondition(guideFunctions[0xc8]?.kind.arity == 0)
        precondition(guideFunctions[0xd1]?.kind.arity == 0)
        precondition(guideFunctions[0xd1]!.invoke([]) == 0)
        precondition(guideFunctions[0x58]!.invoke([1]) == 1)
        precondition(guideState.messageWait)
        precondition(guideFunctions[0x58]!.invoke([0]) == 0)
        precondition(!guideState.messageWait)

        precondition(guideFunctions[0x31]!.invoke([0]) == 0)
        precondition(guideFunctions[0x10]!.invoke([1, 0]) == 0)
        precondition(guideState.messageText == "Welcome Raider!")
        precondition(guideState.messageNeedsAdvance)
        precondition(!guideState.nextArrowDisabled)
        precondition(guideFunctions[0xc8]!.invoke([]) == 0)
        precondition(!guideState.messageNeedsAdvance)
        precondition(guideState.acknowledgedMessageCount == 1)
        precondition(guideFunctions[0xd1]!.invoke([]) == 0)
        // A repeated script call for the same line must not trigger a
        // phantom second player click or duplicate its recent history.
        precondition(guideFunctions[0x10]!.invoke([1, 0]) == 0)
        precondition(!guideState.messageNeedsAdvance)
        precondition(guideFunctions[0xc8]!.invoke([]) == 0)
        precondition(guideState.acknowledgedMessageCount == 1)
        precondition(guideState.recentMessageNumbers == [1])
        // The original tutorial may re-run SetMessagePermit 0 and the same
        // message every frame. One real click must stay acknowledged.
        precondition(guideFunctions[0x31]!.invoke([0]) == 0)
        precondition(guideFunctions[0x10]!.invoke([1, 0]) == 0)
        precondition(!guideState.messageNeedsAdvance)
        precondition(guideState.acknowledgedMessageCount == 1)

        precondition(guideFunctions[0x31]!.invoke([0]) == 0)
        precondition(guideFunctions[0x10]!.invoke([2, 1]) == 0)
        precondition(guideState.nextArrowDisabled)
        precondition(guideState.messageNeedsAdvance)
        precondition(guideState.messageText == "Select the rock.")
        // A script-invoked AdvanceMessage works even when UI Next is
        // disabled, exactly as the original native function dispatch.
        precondition(guideFunctions[0xc8]!.invoke([]) == 0)
        precondition(guideFunctions[0xd1]!.invoke([]) == 1)
        precondition(guideState.recentMessageNumbers == [1, 2])
        precondition(guideState.acknowledgedMessageCount == 2)

        // Source uses unsigned 32-bit conversion for all three delay
        // values. Text-only messages use the original default delay.
        precondition(guideFunctions[0x6b]!.invoke([]) == 4000)
        precondition(guideFunctions[0x6c]!.invoke([1000, -1, 4000]) == 1)
        precondition(guideState.messageTimerValues[0] == 1000)
        precondition(guideState.messageTimerValues[1] == Float(UInt32.max))
        precondition(guideState.messageTimerValues[2] == 4000)
        try guideState.startOriginalMessageAudio(durationMilliseconds: 1500)
        try guideState.advanceTimers(milliseconds: 250.75)
        precondition(guideState.messageTimer == 1249.25)
        precondition(guideFunctions[0x6b]!.invoke([]) == 1249)
        try guideState.advanceTimers(milliseconds: 2000)
        precondition(guideState.messageTimer == 0)
        do {
            try guideState.startOriginalMessageAudio(durationMilliseconds: .infinity)
            preconditionFailure("Accepted an infinite voice duration")
        } catch NativeNERPsGameState.StateError.invalidElapsedTime {}

        // Verify message progress feeds the actual NPL interpreter. A
        // zero-arg predicate allows SetR0 only after both real acknowledgements.
        let messageProgress = NativeNERPsGameState(script: try encode([
            (2, 0xd1), (2, 0x19), (0, 77)
        ]), messages: guide)
        let progressFunctions = messageProgress.functions()
        _ = try messageProgress.tick(elapsedMilliseconds: 10)
        precondition(messageProgress.registers[0] == 0)
        _ = progressFunctions[0x31]!.invoke([0])
        _ = progressFunctions[0x10]!.invoke([1, 0])
        _ = progressFunctions[0xc8]!.invoke([])
        _ = progressFunctions[0x31]!.invoke([0])
        _ = progressFunctions[0x10]!.invoke([2, 0])
        _ = progressFunctions[0xc8]!.invoke([])
        _ = try messageProgress.tick(elapsedMilliseconds: 10)
        precondition(messageProgress.registers[0] == 77)

        // Original NPL 0x50 counts selected Pilot units; it must react
        // to actual selection callbacks from the native OL-driven 3D view.
        let pilotSelection = NativeNERPsGameState(script: try encode([
            (2, 0x50), (2, 0x19), (0, 1)
        ]))
        precondition(pilotSelection.functions()[0x50]!.invoke([]) == 0)
        _ = try pilotSelection.tick(elapsedMilliseconds: 16)
        precondition(pilotSelection.registers[0] == 0)
        pilotSelection.reportRockRaiderSelection(true)
        precondition(pilotSelection.selectedRockRaiderCount == 1)
        precondition(pilotSelection.functions()[0x50]!.invoke([]) == 1)
        _ = try pilotSelection.tick(elapsedMilliseconds: 16)
        precondition(pilotSelection.registers[0] == 1)
        pilotSelection.reportRockRaiderSelection(false)
        precondition(pilotSelection.functions()[0x50]!.invoke([]) == 0)
        precondition(pilotSelection.selectedRockRaiderCount == 0)

        // The first tutorial's NERPs ClickOnly commands must actually
        // restrict terrain clicks, unit selection and camera movement.
        // All mask bits come from src/openlrr/game/mission/NERPsFile.h.
        let freely = NativeTutorialInputPolicy.unrestricted
        precondition(freely.canClickMap && freely.canSelectObjects)
        precondition(freely.canMoveCamera && freely.canClickIcons)
        let flags = NativeTutorialInputPolicy.scriptMask(
            kind: .objects, allowCameraMovementMask: 0)
        precondition(flags == 0x1ff3)
        let objectsPolicy = NativeTutorialInputPolicy(flags: flags)
        precondition(objectsPolicy.canSelectObjects)
        precondition(objectsPolicy.canClickMap)
        precondition(!objectsPolicy.canMoveCamera)
        precondition(!objectsPolicy.canClickIcons)

        let tutorialInput = NativeNERPsGameState(script: try encode([
            (0, 1), (2, 0xc9), (0, 1), // TRUE ? AllowCameraMovement 1
            (0, 1), (2, 0xcb),         // TRUE ? ClickOnlyMap
            (0, 1), (2, 0x19), (2, 0x5d) // SetR0(GetTutorialFlags)
        ]))
        let gatingTick = try tutorialInput.tick(elapsedMilliseconds: 33)
        precondition(gatingTick.actionsExecuted == 3)
        precondition(tutorialInput.tutorialFlags == 0x0ffb)
        precondition(tutorialInput.registers[0] == tutorialInput.tutorialFlags)
        precondition(tutorialInput.inputPolicy.canClickMap)
        precondition(!tutorialInput.inputPolicy.canSelectObjects)
        precondition(tutorialInput.inputPolicy.canMoveCamera)
        precondition(!tutorialInput.inputPolicy.canClickIcons)

        let controls = tutorialInput.functions()
        precondition(controls[0xc9]!.invoke([0]) == 0)
        // Changing the camera setting alone does not rewrite the
        // tutorial mask until a ClickOnly* function runs.
        precondition(tutorialInput.inputPolicy.canMoveCamera)
        precondition(controls[0xcc]!.invoke([]) == 0)
        precondition(tutorialInput.tutorialFlags == 0x1ffe)
        precondition(tutorialInput.inputPolicy.canClickIcons)
        precondition(!tutorialInput.inputPolicy.canClickMap)
        precondition(!tutorialInput.inputPolicy.canSelectObjects)
        precondition(!tutorialInput.inputPolicy.canMoveCamera)

        precondition(controls[0xca]!.invoke([]) == 0)
        precondition(tutorialInput.tutorialFlags == 0x1ff3)
        precondition(tutorialInput.inputPolicy.canClickMap)
        precondition(tutorialInput.inputPolicy.canSelectObjects)
        precondition(!tutorialInput.inputPolicy.canMoveCamera)

        precondition(controls[0xcd]!.invoke([]) == 0)
        precondition(tutorialInput.tutorialFlags == 0x1fff)
        precondition(!tutorialInput.inputPolicy.canClickMap)
        precondition(!tutorialInput.inputPolicy.canSelectObjects)
        precondition(!tutorialInput.inputPolicy.canMoveCamera)

        precondition(controls[0xc9]!.invoke([1]) == 0)
        precondition(controls[0xcd]!.invoke([]) == 0)
        precondition(tutorialInput.tutorialFlags == 0x0fff)
        precondition(!tutorialInput.inputPolicy.canClickMap)
        precondition(tutorialInput.inputPolicy.canMoveCamera)
        precondition(controls[0xce]!.invoke([1]) == 0)
        precondition(tutorialInput.suppressMessageArrow)
        precondition(controls[0xce]!.invoke([0]) == 0)
        precondition(!tutorialInput.suppressMessageArrow)
        precondition(controls[0x5e]!.invoke([0]) == 0)
        precondition(tutorialInput.inputPolicy.canSelectObjects)
        precondition(tutorialInput.inputPolicy.canClickMap)

        // Original script dispatch queries live world callbacks each tick.
        let worldScript = NativeNERPsGameState(script: try encode([
            (2, 0x72), (0, 1), (1, 5), (0, 0), (2, 0x19), (0, 42),
            (2, 1), (2, 0x73), (0, 2),
            (2, 0x8f), (0, 2), (2, 0x1a), (2, 0x34)
        ]))
        var ground: Int32 = 0
        var cameraTarget: Int32 = -1
        worldScript.tutorialGroundValue = { id in precondition(id == 1); return ground }
        worldScript.gotoTutorialCamera = { cameraTarget = $0 }
        worldScript.cameraAtTutorial = { $0 == cameraTarget ? 1 : 0 }
        worldScript.rockRaidersOnLevel = { 3 }
        _ = try worldScript.tick(elapsedMilliseconds: 0)
        precondition(worldScript.registers[0] == 0 && worldScript.registers[1] == 3)
        ground = 8
        _ = try worldScript.tick(elapsedMilliseconds: 0)
        precondition(worldScript.registers[0] == 42)

        // Separate level sessions cannot accidentally share runtime state.
        let fresh = NativeNERPsGameState(script: try encode([]))
        precondition(fresh.registers == Array(repeating: 0, count: 8))
        precondition(fresh.timers == Array(repeating: 0, count: 4))
        print("PASS: persistent NERPs register, timer and tutorial-state callbacks")
    }

    static func initialBriefingBridge() throws {
        // A live UI query, not BF/C0's consumable notification. Both ordinary
        // conditions and nested zero-argument expressions use retail ID 0x32.
        let state = NativeNERPsGameState(script: try encode([
            (2, 0x32), (2, 0x21), (0, 1), // While showing: AddR0(1)
            (2, 0xc0), (2, 0x22), (0, 1), // On dismissal: AddR1(1)
            (2, 1), (2, 0x1b), (2, 0x32), // SetR2(GetObjectiveShowing)
            (2, 1), (2, 0x24), (0, 1) // Count every running tick in R3
        ]))
        let callbacks = state.functions()
        precondition(callbacks[0x32]!.kind.arity == 0 && !callbacks[0x32]!.kind.isAction)
        precondition(callbacks[0x32]!.invoke([]) == 0, "No attached overlay means not showing")
        precondition(state.objectiveSwitch == 0)
        var showing = true
        state.objectiveShowing = { showing }
        precondition(callbacks[0x32]!.invoke([]) == 1)
        precondition(callbacks[0x32]!.invoke([]) == 1, "Showing query must not consume visibility")
        try state.startOriginalMessageAudio(durationMilliseconds: 2500)

        // The original update still runs bytecode during briefing while
        // elapsedInterface is zero. Registers progress; both timer types do not.
        for _ in 0..<2 { _ = try state.tick(elapsedMilliseconds: 0) }
        precondition(state.completedTicks == 2)
        precondition(Array(state.registers.prefix(4)) == [2, 0, 1, 2])
        precondition(state.timers == Array(repeating: 0, count: 4))
        precondition(state.messageTimer == 2500 && state.objectiveSwitch == 0)

        // Explicit diagnostic pause is distinct: even zero-elapsed bytecode
        // must not execute. Time spent paused is not passed on to resume.
        state.isPaused = true
        let paused = try state.tick(elapsedMilliseconds: 10_000)
        precondition(paused.visitedInstructions == 0 && paused.functionCalls == 0)
        precondition(state.completedTicks == 2 && state.registers[3] == 2)
        precondition(state.timers[0] == 0 && state.messageTimer == 2500)
        state.isPaused = false
        showing = false
        precondition(callbacks[0x32]!.invoke([]) == 0)
        precondition(state.objectiveSwitch == 0, "Visibility alone must not fire the dismissal latch")
        precondition(state.reportInitialBriefingDismissed())
        precondition(state.objectiveSwitch == 1)
        precondition(!state.reportInitialBriefingDismissed())
        _ = try state.tick(elapsedMilliseconds: 16)
        precondition(Array(state.registers.prefix(4)) == [2, 1, 0, 3])
        precondition(state.timers[0] == 16 && state.messageTimer == 2484)
        precondition(state.objectiveSwitch == 0)
        precondition(!state.reportInitialBriefingDismissed(), "Repeated dismissal after consumption cannot re-arm")
        _ = try state.tick(elapsedMilliseconds: 16)
        precondition(state.registers[1] == 1 && state.registers[3] == 4)
        precondition(state.timers[0] == 32 && state.messageTimer == 2468)

        // The UI guard does not change the original script's BF/C0 semantics.
        precondition(callbacks[0xbf]!.invoke([7]) == 7)
        precondition(!state.reportInitialBriefingDismissed())
        precondition(state.objectiveSwitch == 7)
        precondition(callbacks[0xc0]!.invoke([]) == 1)
        precondition(callbacks[0xc0]!.invoke([]) == 0)
        state.objectiveShowing = nil
        precondition(callbacks[0x32]!.invoke([]) == 0 && state.objectiveSwitch == 0)

        // 0xC1 is NOT GetObjectiveShowing. Preserve unsupported-opcode halting
        // rather than accepting a mistaken alias or inventing that function.
        precondition(callbacks[0xc1] == nil)
        let unsupported = NativeNERPsGameState(script: try encode([(2, 0xc1)]))
        do {
            _ = try unsupported.tick(elapsedMilliseconds: 0)
            preconditionFailure("Unsupported 0xC1 was treated as GetObjectiveShowing")
        } catch NERPsRuntime.RuntimeError.missingSignature(let pc, let id) {
            precondition(pc == 0 && id == 0xc1 && unsupported.completedTicks == 0)
        }

        // New missions receive a fresh one-shot guard; removing a view without
        // reporting dismissal cannot accidentally start the next script stage.
        let next = NativeNERPsGameState(script: try encode([]))
        next.objectiveShowing = { true }
        next.objectiveShowing = nil
        precondition(next.objectiveSwitch == 0)
        precondition(next.reportInitialBriefingDismissed())
        precondition(next.functions()[0xc0]!.invoke([]) == 1)
    }
    static func openingBriefingDoesNotBypassScript() throws {
        var briefing = try OriginalMissionBriefingState(pageCount: 1, openingInput: .init(leftDown: true))
        let runtime = NativeNERPsGameState(script: try encode([
            (2, 0x32), (1, 7), (0, 0), (2, 0x21), (0, 1), // !showing: AddR0(1)
            (2, 0x32), (2, 0x22), (0, 1) // showing: AddR1(1)
        ]))
        runtime.objectiveShowing = { briefing.isShowing }
        precondition(!briefing.isShowing && !briefing.permitsScriptTick)
        for _ in 0..<5 {
            if briefing.permitsScriptTick { _ = try runtime.tick(elapsedMilliseconds: 0) }
        }
        precondition(runtime.completedTicks == 0 && runtime.registers[0] == 0,
                     "Opening mouse drain must not let !GetObjectiveShowing bypass the initial brief")
        precondition(briefing.update(.init()) == .none)
        precondition(briefing.permitsScriptTick && briefing.isShowing)
        if briefing.permitsScriptTick { _ = try runtime.tick(elapsedMilliseconds: 0) }
        precondition(runtime.completedTicks == 1 && runtime.registers[0] == 0 && runtime.registers[1] == 1)
        precondition(runtime.timers[0] == 0, "Visible briefing ticks without interface elapsed time")
        precondition(briefing.update(.init(spaceDown: true)) == .dismissed)
        precondition(briefing.permitsScriptTick)
        _ = try runtime.tick(elapsedMilliseconds: 0)
        precondition(runtime.registers[0] == 1 && runtime.registers[1] == 1)
    }

}
