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

        // The original OpenLRR functions use signed 32-bit registers.
        let callbacks = state.functions()
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
        // values. GetMessageTimer must return zero until authentic audio
        // has actually supplied a duration.
        precondition(guideFunctions[0x6b]!.invoke([]) == 0)
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

        // Separate level sessions cannot accidentally share runtime state.
        let fresh = NativeNERPsGameState(script: try encode([]))
        precondition(fresh.registers == Array(repeating: 0, count: 8))
        precondition(fresh.timers == Array(repeating: 0, count: 4))
        print("PASS: persistent NERPs register, timer and tutorial-state callbacks")
    }
}
