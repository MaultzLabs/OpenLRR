import Foundation

/// Read-only decoder for the retail game's compiled NERPs '.npl' bytecode.
/// OpenLRR's NERPsInstruction is a 4-byte little-endian record containing a
/// UInt16 operand followed by a UInt16 opcode. See NERPsFile.h and
/// NERPsRuntime_Execute in NERPsFile.cpp. This does not execute game logic.
struct NERPsScript {
    enum ScriptError: Error, CustomStringConvertible {
        case invalid(String)
        case missingLevelScript(String)

        var description: String {
            switch self {
            case .invalid(let reason): return "Invalid NERPs bytecode: \(reason)"
            case .missingLevelScript(let level): return "No NERPFile configured for \(level)"
            }
        }
    }

    enum Opcode: UInt16 {
        case literal = 0
        case `operator` = 1
        case function = 2
        case label = 4
        case jump = 8
    }

    struct Instruction {
        let opcode: Opcode
        let operand: UInt16

        /// The original interpreter sign-extends 16-bit integer literals.
        var signedLiteral: Int16? {
            opcode == .literal ? Int16(bitPattern: operand) : nil
        }

        /// Names and order from c_nerpsOperators in OpenLRR NERPsFile.cpp.
        var operatorSymbol: String? {
            guard opcode == .operator else { return nil }
            return ["+", "#", "/", "\\", "?", ">", "<", "=", ">=", "<=", "!="][Int(operand)]
        }
    }

    let instructions: [Instruction]

    init(data: Data) throws {
        // A bounded, strictly read-only parse: no allocation based on any
        // embedded pointer or offset, and no attempt to run a NERPs function.
        guard data.count <= 4_000_000, data.count.isMultiple(of: 4) else {
            throw ScriptError.invalid("file must contain at most 1,000,000 complete 4-byte instructions")
        }
        let count = data.count / 4
        var decoded: [Instruction] = []
        decoded.reserveCapacity(count)
        for index in 0..<count {
            let start = index * 4
            let operand = UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
            let rawOpcode = UInt16(data[start + 2]) | (UInt16(data[start + 3]) << 8)
            guard let opcode = Opcode(rawValue: rawOpcode) else {
                throw ScriptError.invalid("unknown opcode \(rawOpcode) at instruction \(index)")
            }
            switch opcode {
            case .operator:
                guard operand <= 10 else {
                    throw ScriptError.invalid("unknown operator \(operand) at instruction \(index)")
                }
            case .function:
                // OpenLRR's retail c_nerpsFunctions has 294 entries, IDs 0...293.
                guard operand < 294 else {
                    throw ScriptError.invalid("function ID out of range at instruction \(index)")
                }
            case .jump:
                // NERPsRuntime_Execute sets instrIdx to the operand, then the
                // for-loop increments it. The end index is a valid exit.
                guard Int(operand) <= count else {
                    throw ScriptError.invalid("jump beyond script at instruction \(index)")
                }
            case .literal, .label:
                break
            }
            decoded.append(Instruction(opcode: opcode, operand: operand))
        }
        instructions = decoded
    }

    /// Resolve the exact compiled script named by this level's 'NERPFile'
    /// setting, using only the explicitly mounted user-owned WAD archives.
    static func load(levelIdentifier: String, config: LegoConfig,
                     resources: GameResources) throws -> NERPsScript {
        let parts = levelIdentifier.components(separatedBy: "::")
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }),
              let path = config.valueUnderGame(parts + ["NERPFile"]),
              !path.isEmpty else {
            throw ScriptError.missingLevelScript(levelIdentifier)
        }
        guard path.lowercased().hasSuffix(".npl") else {
            throw ScriptError.invalid("configured script is not an NPL file")
        }
        return try NERPsScript(data: resources.data(at: path, maximumBytes: 4_000_000))
    }

    var instructionCount: Int { instructions.count }
}
