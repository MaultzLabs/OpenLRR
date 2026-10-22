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

        // Separate level sessions cannot accidentally share runtime state.
        let fresh = NativeNERPsGameState(script: try encode([]))
        precondition(fresh.registers == Array(repeating: 0, count: 8))
        precondition(fresh.timers == Array(repeating: 0, count: 4))
        print("PASS: persistent NERPs register, timer and tutorial-state callbacks")
    }
}
