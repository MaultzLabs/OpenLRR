import Foundation

private func word(_ value: UInt16) -> [UInt8] {
    [UInt8(truncatingIfNeeded: value), UInt8(truncatingIfNeeded: value >> 8)]
}
private func instruction(_ operand: UInt16, _ opcode: UInt16) -> [UInt8] {
    word(operand) + word(opcode)
}
private func expectFailure(_ name: String, _ run: () throws -> Void) {
    do { try run(); preconditionFailure("Accepted invalid NPL: \(name)") }
    catch is NERPsScript.ScriptError { print("Rejected \(name)") }
    catch { preconditionFailure("Unexpected error for \(name): \(error)") }
}
private func le(_ n: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
     UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
}
private func archive(_ files: [(String, [UInt8])]) -> Data {
    var bytes: [UInt8] = [87,87,65,68] + le(UInt32(files.count))
    for (name, _) in files { bytes += Array(name.utf8) + [0] }
    for (name, _) in files { bytes += Array(("C:\\Build\\" + name).utf8) + [0] }
    var offset = bytes.count + files.count * 16
    for (_, payload) in files {
        bytes += le(1) + le(UInt32(payload.count)) + le(UInt32(payload.count)) + le(UInt32(offset))
        offset += payload.count
    }
    for (_, payload) in files { bytes += payload }
    return Data(bytes)
}

@main struct NERPsScriptTests {
    static func main() throws {
        // All data is synthetic; no original scripts or game assets are used.
        let binary = Data(instruction(0xffff, 0) + // literal -1
                          instruction(13, 2) +     // function 13
                          instruction(5, 1) +      // operator >
                          instruction(0, 4) +      // label 0
                          instruction(4, 8) +      // jump to last instruction
                          instruction(0, 2))       // Stop function
        let script = try NERPsScript(data: binary)
        precondition(script.instructionCount == 6)
        precondition(script.instructions[0].signedLiteral == -1)
        precondition(script.instructions[1].opcode == .function)
        precondition(script.instructions[2].operatorSymbol == ">")
        precondition(script.instructions[4].opcode == .jump)
        precondition(script.instructions[5].operand == 0)
        let prefixed = Data([0xAA, 0xBB] + Array(binary))
        let sliced = prefixed.dropFirst(2)
        precondition(sliced.startIndex != 0)
        let slicedScript = try NERPsScript(data: sliced)
        precondition(slicedScript.instructionCount == script.instructionCount)
        precondition(slicedScript.instructions[0].signedLiteral == -1)
        let highFunction = try NERPsScript(data: Data(instruction(293, 2)))
        precondition(highFunction.instructionCount == 1)
        let endJump = try NERPsScript(data: Data(instruction(1, 8)))
        precondition(endJump.instructionCount == 1)
        let emptyScript = try NERPsScript(data: Data())
        precondition(emptyScript.instructionCount == 0)

        expectFailure("truncated instruction") {
            _ = try NERPsScript(data: Data(binary.dropLast()))
        }
        expectFailure("unknown opcode") {
            _ = try NERPsScript(data: Data(instruction(0, 16)))
        }
        expectFailure("combined opcode flags") {
            _ = try NERPsScript(data: Data(instruction(0, 3)))
        }
        expectFailure("unknown operator") {
            _ = try NERPsScript(data: Data(instruction(11, 1)))
        }
        expectFailure("invalid function index") {
            _ = try NERPsScript(data: Data(instruction(294, 2)))
        }
        expectFailure("jump beyond script") {
            _ = try NERPsScript(data: Data(instruction(2, 8)))
        }
        expectFailure("oversized bytecode") {
            _ = try NERPsScript(data: Data(repeating: 0, count: 4_000_004))
        }

        let cfg = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              NERPFile Levels\\GameLevels\\Level01\\01.npl
            }
          }
        }
        """)
        let resources = try GameResources(archives: [(0, archive([
            ("Levels\\GameLevels\\Level01\\01.npl", Array(binary))
        ]))])
        let loaded = try NERPsScript.load(levelIdentifier: "Levels::Level01",
                                          config: cfg, resources: resources)
        precondition(loaded.instructionCount == script.instructionCount)
        expectFailure("missing level script") {
            _ = try NERPsScript.load(levelIdentifier: "Levels::Level02",
                                     config: cfg, resources: resources)
        }
        let wrongExtension = try LegoConfig(text: "Lego* { Levels { Level01 { NERPFile 01.nrn } } }")
        expectFailure("non-bytecode source path") {
            _ = try NERPsScript.load(levelIdentifier: "Levels::Level01",
                                     config: wrongExtension, resources: resources)
        }
        print("PASS: original NPL opcode decoding, bounds checks, CFG/WAD level script loading")
    }
}
