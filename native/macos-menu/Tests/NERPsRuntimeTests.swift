import Foundation

private func word(_ value: UInt16) -> [UInt8] {
    [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
}
private func script(_ pairs: [(NERPsScript.Opcode, UInt16)]) throws -> NERPsScript {
    try NERPsScript(data: Data(pairs.flatMap { word($0.1) + word($0.0.rawValue) }))
}
private func mustThrow(_ title: String, _ block: () throws -> Void) {
    do {
        try block()
        preconditionFailure("Unexpectedly accepted \(title)")
    } catch is NERPsRuntime.RuntimeError {
        print("Correctly rejected \(title)")
    } catch {
        preconditionFailure("Unexpected error in \(title): \(error)")
    }
}

@main struct NERPsRuntimeTests {
    static func main() throws {
        // The original C++ runtime evaluates literal signed values and
        // calls the action only when the expression is true.
        let instructions: [(NERPsScript.Opcode, UInt16)] = [
            (.literal, 1), (.operator, 5), (.literal, 0),
            (.function, 3), (.literal, 0xffff), (.literal, 7),
            (.function, 0)
        ]
        var values: [[Int32]] = []
        var logged: [NERPsRuntime.Call] = []
        let action = NERPsRuntime.Function(kind: .action(arity: 2)) { args in
            values.append(args)
            return 0
        }
        let result = try NERPsRuntime.run(script(instructions),
                                          functions: [3: action],
                                          onCall: { logged.append($0) })
        precondition(values == [[-1, 7]])
        precondition(result.actionsExecuted == 1 && result.stoppedByStopFunction)
        precondition(logged.count == 1 && logged[0].programCounter == 3)

        // False actions must not evaluate nested zero-argument functions.
        var nestedCount = 0
        let falseAction = try script([
            (.literal, 0), (.function, 4), (.function, 2), (.function, 0)
        ])
        let kinds: [Int: NERPsRuntime.Function] = [
            4: .init(kind: .action(arity: 1)) { _ in
                preconditionFailure("False action must not fire")
            },
            2: .init(kind: .expression(arity: 0)) { _ in
                nestedCount += 1
                return -9
            },
            0: .init(kind: .expression(arity: 0)) { _ in 0 }
        ]
        let suppressed = try NERPsRuntime.run(falseAction, functions: kinds)
        precondition(suppressed.actionsExecuted == 0 && nestedCount == 0)

        // True action should evaluate nested zero-arg function argument.
        let trueAction = try script([
            (.literal, 1), (.function, 4), (.function, 2), (.function, 0)
        ])
        var forwarded: [Int32] = []
        let callbacks: [Int: NERPsRuntime.Function] = [
            4: .init(kind: .action(arity: 1)) { args in forwarded = args; return 0 },
            2: .init(kind: .expression(arity: 0)) { _ in -9 }
        ]
        var calls: [NERPsRuntime.Call] = []
        let tick = try NERPsRuntime.run(trueAction, functions: callbacks,
                                        onCall: { calls.append($0) })
        precondition(tick.functionCalls == 2 && tick.actionsExecuted == 1)
        precondition(forwarded == [-9])
        precondition(calls.map(\.functionID) == [2, 4])

        // Retail comparison temporaries are unsigned UInt32 even though
        // literal values are signed Int16; -1 > 1 is true as UInt32.
        let unsigned = try script([
            (.literal, 0xffff), (.operator, 5), (.literal, 1),
            (.function, 4), (.function, 0)
        ])
        let zeroAction = NERPsRuntime.Function(kind: .action(arity: 0)) { _ in 0 }
        let unsignedTick = try NERPsRuntime.run(unsigned, functions: [4: zeroAction])
        precondition(unsignedTick.actionsExecuted == 1)

        // "Pound" (#) applies unary NOT to the next expression.
        let invert = try script([
            (.operator, 1), (.literal, 0), (.function, 4), (.function, 0)
        ])
        let invertedTick = try NERPsRuntime.run(invert, functions: [4: zeroAction])
        precondition(invertedTick.actionsExecuted == 1)

        // A taken jump goes to operand+1, skipping index 2.
        let jump = try script([
            (.literal, 1), (.jump, 2), (.literal, 0),
            (.literal, 1), (.function, 4), (.function, 0)
        ])
        let jumped = try NERPsRuntime.run(jump, functions: [4: zeroAction])
        precondition(jumped.actionsExecuted == 1)

        let stop = try NERPsRuntime.run(script([(.function, 0)]), functions: [:])
        precondition(stop.stoppedByStopFunction)

        mustThrow("unimplemented 294-table function") {
            _ = try NERPsRuntime.run(script([(.function, 90)]), functions: [:])
        }
        mustThrow("truncated function arguments") {
            _ = try NERPsRuntime.run(script([(.literal, 1), (.function, 5)]),
                                      functions: [5: .init(kind: .action(arity: 2)) { _ in 0 }])
        }
        mustThrow("invalid action arity") {
            _ = try NERPsRuntime.run(script([(.function, 5)]),
                                      functions: [5: .init(kind: .action(arity: 4)) { _ in 0 }])
        }
        mustThrow("backwards bytecode loop limit") {
            _ = try NERPsRuntime.run(
                script([(.label, 0), (.literal, 1), (.jump, 0)]),
                functions: [:], maxSteps: 20)
        }
        print("PASS: native NERPs bytecode interpreter actions, arguments, comparison, jumps and bounded safety")
    }
}
