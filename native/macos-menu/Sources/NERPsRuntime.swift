import Foundation

/// Native interpreter for the original NERPs control flow documented by
/// OpenLRR's NERPsRuntime_Execute in src/openlrr/game/mission/NERPsFile.cpp.
/// Function IDs require explicit native callbacks. No call into LegoRR.exe.
struct NERPsRuntime {
    enum RuntimeError: Error, CustomStringConvertible {
        case missingSignature(pc: Int, functionID: Int)
        case truncatedArguments(pc: Int, expected: Int)
        case tooManyInstructions(limit: Int)
        case invalidSignature(functionID: Int, arity: Int)

        var description: String {
            switch self {
            case .missingSignature(let pc, let id):
                return "Unimplemented NERPs function \(id) at PC \(pc)"
            case .truncatedArguments(let pc, let n):
                return "NERPs function at PC \(pc) requires \(n) argument words"
            case .tooManyInstructions(let limit):
                return "NERPs tick exceeded \(limit) interpreter steps"
            case .invalidSignature(let id, let n):
                return "Invalid NERPs arity \(n) for function \(id)"
            }
        }
    }

    enum Kind {
        case expression(arity: Int)
        case action(arity: Int)

        var arity: Int {
            switch self {
            case .expression(let n), .action(let n): return n
            }
        }
        var isAction: Bool {
            switch self {
            case .action: return true
            case .expression: return false
            }
        }
    }

    struct Function {
        let kind: Kind
        let invoke: ([Int32]) -> Int32
    }

    struct Call {
        let programCounter: Int
        let functionID: Int
        let arguments: [Int32]
        let result: Int32
        let isAction: Bool
    }

    struct Tick {
        let visitedInstructions: Int
        let functionCalls: Int
        let actionsExecuted: Int
        let stoppedByStopFunction: Bool
    }

    private enum Comparison {
        case none, and, or, greater, less, equal, greaterOrEqual, lessOrEqual, notEqual

        func apply(_ lhs: UInt32, _ rhs: UInt32) -> UInt32 {
            switch self {
            case .none: return rhs
            case .and: return lhs != 0 && rhs != 0 ? 1 : 0
            case .or: return lhs != 0 || rhs != 0 ? 1 : 0
            case .greater: return lhs > rhs ? 1 : 0
            case .less: return lhs < rhs ? 1 : 0
            case .equal: return lhs == rhs ? 1 : 0
            case .greaterOrEqual: return lhs >= rhs ? 1 : 0
            case .lessOrEqual: return lhs <= rhs ? 1 : 0
            case .notEqual: return lhs != rhs ? 1 : 0
            }
        }
    }

    /// The retail interpreter re-evaluates each script from PC=0 on every
    /// update; persistent registers/timers/game state belong to callbacks.
    /// maxSteps adds a guard against hanging on malformed original bytecode.
    static func run(_ script: NERPsScript, functions: [Int: Function],
                    maxSteps: Int = 200_000,
                    onCall: ((Call) -> Void)? = nil) throws -> Tick {
        guard maxSteps > 0 else { throw RuntimeError.tooManyInstructions(limit: maxSteps) }
        let ins = script.instructions
        var pc = 0
        var visited = 0
        var calls = 0
        var actions = 0
        var regA: UInt32 = 0
        var negate = false
        var cmp = Comparison.none
        var nextCmp = Comparison.none
        var stoppedByStop = false

        // Each argument is the raw 4-byte instruction except integer
        // literals (signed) and zero-argument expression-function literals.
        func argValue(at index: Int) throws -> Int32 {
            let item = ins[index]
            if item.opcode == .function, functions[Int(item.operand)] == nil {
                throw RuntimeError.missingSignature(pc: index, functionID: Int(item.operand))
            }
            if item.opcode == .function,
               let nested = functions[Int(item.operand)],
               !nested.kind.isAction && nested.kind.arity == 0 {
                let value = nested.invoke([])
                calls += 1
                onCall?(Call(programCounter: index, functionID: Int(item.operand),
                             arguments: [], result: value, isAction: false))
                return value
            }
            if item.opcode == .literal {
                return Int32(Int16(bitPattern: item.operand))
            }
            let raw = UInt32(item.operand) | (UInt32(item.opcode.rawValue) << 16)
            return Int32(bitPattern: raw)
        }

        while pc < ins.count {
            if visited >= maxSteps { throw RuntimeError.tooManyInstructions(limit: maxSteps) }
            visited += 1
            let item = ins[pc]
            cmp = nextCmp
            nextCmp = cmp
            switch item.opcode {
            case .function:
                let id = Int(item.operand)
                if id == 0 && (regA != 0 || cmp == .none) {
                    stoppedByStop = true
                    pc = ins.count
                    continue
                }
                guard let function = functions[id] else {
                    throw RuntimeError.missingSignature(pc: pc, functionID: id)
                }
                let arity = function.kind.arity
                guard arity >= 0 && arity <= (function.kind.isAction ? 3 : 2) else {
                    throw RuntimeError.invalidSignature(functionID: id, arity: arity)
                }
                guard arity <= ins.count - pc - 1 else {
                    throw RuntimeError.truncatedArguments(pc: pc, expected: arity)
                }
                if function.kind.isAction {
                    // False actions DO NOT resolve nested function arguments.
                    if regA != 0 {
                        var values: [Int32] = []
                        for at in 0..<arity { values.append(try argValue(at: pc + 1 + at)) }
                        let result = function.invoke(values)
                        calls += 1
                        actions += 1
                        onCall?(Call(programCounter: pc, functionID: id,
                                     arguments: values, result: result, isAction: true))
                    }
                    regA = 0
                    negate = false
                    nextCmp = .none
                } else {
                    var values: [Int32] = []
                    for at in 0..<arity { values.append(try argValue(at: pc + 1 + at)) }
                    let result = function.invoke(values)
                    calls += 1
                    onCall?(Call(programCounter: pc, functionID: id,
                                 arguments: values, result: result, isAction: false))
                    var regB = UInt32(bitPattern: result)
                    if negate { regB = regB == 0 ? 1 : 0 }
                    regA = cmp.apply(regA, regB)
                    negate = false
                    nextCmp = .and
                }
                pc += 1 + arity
            case .operator:
                switch item.operand {
                case 0: negate = false; nextCmp = .and
                case 1: negate = true
                case 2: negate = false; nextCmp = .or
                case 5: negate = false; nextCmp = .greater
                case 6: negate = false; nextCmp = .less
                case 7: negate = false; nextCmp = .equal
                case 8: negate = false; nextCmp = .greaterOrEqual
                case 9: negate = false; nextCmp = .lessOrEqual
                case 10: negate = false; nextCmp = .notEqual
                default: negate = false // Backslash and test have no effect.
                }
                pc += 1
            case .label:
                regA = 0
                negate = false
                nextCmp = .none
                pc += 1
            case .jump:
                // NERPsRuntime_Execute sets PC=operand then increments it.
                pc = regA != 0 ? Int(item.operand) + 1 : pc + 1
                regA = 0
                negate = false
                nextCmp = .none
            case .literal:
                var regB = UInt32(bitPattern: Int32(Int16(bitPattern: item.operand)))
                if negate { regB = regB == 0 ? 1 : 0 }
                regA = cmp.apply(regA, regB)
                negate = false
                nextCmp = .and
                pc += 1
            }
        }
        return Tick(visitedInstructions: visited, functionCalls: calls,
                    actionsExecuted: actions, stoppedByStopFunction: stoppedByStop)
    }
}
