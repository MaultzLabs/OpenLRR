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

        // Separate level sessions cannot accidentally share runtime state.
        let fresh = NativeNERPsGameState(script: try encode([]))
        precondition(fresh.registers == Array(repeating: 0, count: 8))
        precondition(fresh.timers == Array(repeating: 0, count: 4))
        print("PASS: persistent NERPs register, timer and tutorial-state callbacks")
    }
}
