import Foundation

/// Persistent, source-grounded mission state for the original NERPs VM.
/// IDs follow the retail NPL function table (RRU NERPs documentation);
/// effects follow src/openlrr/game/mission/NERPsFunctions.cpp and
/// NERPsRuntime_UpdateTimers in NERPsFile.cpp. No simulated units or resources.
final class NativeNERPsGameState {
    enum StateError: Error {
        case invalidElapsedTime
    }

    let script: NERPsScript
    private(set) var registers = [Int32](repeating: 0, count: 8)
    private(set) var timers = [Float](repeating: 0, count: 4)
    private(set) var tutorialFlags: Int32 = 0
    private(set) var completedTicks = 0

    init(script: NERPsScript) {
        self.script = script
    }

    /// Receives real frame elapsed time in milliseconds, instead of
    /// assuming a fabricated game framerate. Retail timers are float32
    /// milliseconds and continue across repeated interpreter invocations.
    func advanceTimers(milliseconds: Float) throws {
        guard milliseconds.isFinite, milliseconds >= 0,
              milliseconds <= 600_000,
              timers.allSatisfy({ ($0 + milliseconds).isFinite }) else {
            throw StateError.invalidElapsedTime
        }
        for i in timers.indices { timers[i] += milliseconds }
    }

    func tick(elapsedMilliseconds: Float, maxSteps: Int = 200_000,
              onCall: ((NERPsRuntime.Call) -> Void)? = nil) throws -> NERPsRuntime.Tick {
        try advanceTimers(milliseconds: elapsedMilliseconds)
        let result = try NERPsRuntime.run(script, functions: functions(),
                                          maxSteps: maxSteps, onCall: onCall)
        completedTicks += 1
        return result
    }

    /// Only proven functions are available. If bytecode reaches another ID,
    /// NERPsRuntime throws rather than manufacturing gameplay outcomes.
    func functions() -> [Int: NERPsRuntime.Function] {
        var callbacks: [Int: NERPsRuntime.Function] = [:]
        callbacks[0] = .init(kind: .action(arity: 0), invoke: { _ in 0 }) // Stop
        for i in 0..<8 {
            let slot = i
            callbacks[0x11 + i] = .init(kind: .expression(arity: 0),
                                        invoke: { [unowned self] _ in self.registers[slot] })
            callbacks[0x19 + i] = .init(kind: .action(arity: 1),
                                        invoke: { [unowned self] args in
                self.registers[slot] = args[0]
                return self.registers[slot]
            })
            callbacks[0x21 + i] = .init(kind: .action(arity: 1),
                                        invoke: { [unowned self] args in
                // Original signed 32-bit C++ addition/subtraction, made
                // deterministic on overflow rather than trapping in Swift.
                self.registers[slot] = self.registers[slot] &+ args[0]
                return self.registers[slot]
            })
            callbacks[0x29 + i] = .init(kind: .action(arity: 1),
                                        invoke: { [unowned self] args in
                self.registers[slot] = self.registers[slot] &- args[0]
                return self.registers[slot]
            })
        }
        for i in 0..<4 {
            let slot = i
            callbacks[0x43 + i] = .init(kind: .expression(arity: 0),
                                        invoke: { [unowned self] _ in
                // Do not trap when a malformed session passes the signed
                // conversion limit; normal retail timers are far smaller.
                let value = self.timers[slot]
                return Int32(max(Float(Int32.min),
                                 min(Float(Int32.max - 256), value)))
            })
            callbacks[0x47 + i] = .init(kind: .action(arity: 1),
                                        invoke: { [unowned self] args in
                self.timers[slot] = Float(UInt32(bitPattern: args[0]))
                return 1
            })
        }
        callbacks[0x5d] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in self.tutorialFlags })
        callbacks[0x5e] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.tutorialFlags = args[0]
            return self.tutorialFlags
        })
        return callbacks
    }
}
