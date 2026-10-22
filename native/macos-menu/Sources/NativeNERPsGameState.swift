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
    // NERPFunc__GetObjectiveSwitch consumes the one-shot objective signal.
    // This is a script-visible latch, not an invented mission-completion UI.
    private(set) var objectiveSwitch: Int32 = 0
    private(set) var tutorialFlags: Int32 = 0
    // Source: NERPFunc__AllowCameraMovement in NERPsFunctions.cpp stores
    // a 0x1000 flag, later cleared from restrictive tutorial masks.
    private(set) var allowCameraMovement = false
    private(set) var completedTicks = 0
    // In retail NERPs, 0 permits messages; nonzero suppresses them.
    private(set) var messagePermit = true
    private(set) var messageText: String?
    private(set) var lastMessageNumber: Int32?
    private(set) var nextArrowDisabled = false
    private let messages: NativeNERPsMessageFile?

    init(script: NERPsScript, messages: NativeNERPsMessageFile? = nil) {
        self.script = script
        self.messages = messages
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
        // Original NPL IDs 0xBF / 0xC0: objective switch is a one-shot
        // notification. GetObjectiveSwitch returns true once and clears it
        // (NERPsFunctions.cpp), not the current objective's visible state.
        callbacks[0xbf] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.objectiveSwitch = args[0]
            return args[0]
        })
        callbacks[0xc0] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in
            guard self.objectiveSwitch != 0 else { return 0 }
            self.objectiveSwitch = 0
            return 1
        })
        // Original NPL function IDs: SetMessagePermit and SetMessage.
        callbacks[0x31] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.messagePermit = args[0] != 0
            self.messageText = nil
            self.lastMessageNumber = nil
            return args[0]
        })
        callbacks[0x10] = .init(kind: .action(arity: 2),
                                invoke: { [unowned self] args in
            guard !self.messagePermit else { return 0 }
            self.lastMessageNumber = args[0]
            self.messageText = self.messages?.text(for: args[0])
            self.nextArrowDisabled = args[1] != 0
            return 0
        })
        callbacks[0x5d] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in self.tutorialFlags })
        callbacks[0x5e] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.tutorialFlags = args[0]
            return self.tutorialFlags
        })

        // Original NPL IDs from RRU's NERPs function table (0xC9-0xCD).
        // C++ implementations: NERPsFunctions.cpp::NERPFunc__AllowCameraMovement,
        // ClickOnlyObjects, ClickOnlyMap, ClickOnlyIcon, DisallowAll.
        //
        // These set DISABLE bits for the UI, rather than fabricating mission
        // progress. There is still no native implementation for most tasks.
        callbacks[0xc9] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.allowCameraMovement = args[0] != 0
            return 0
        })
        func clickOnly(_ enabledBits: UInt32) -> NERPsRuntime.Function {
            .init(kind: .action(arity: 0), invoke: { [unowned self] _ in
                var disabled = NativeTutorialInputPolicy.allDisabledMask & ~enabledBits
                if self.allowCameraMovement { disabled &= ~UInt32(0x1000) }
                self.tutorialFlags = Int32(bitPattern: disabled)
                return 0
            })
        }
        // ClickOnlyObjects also enables map targeting: original C++ clears
        // NOMAP | NOOBJECTS. This is unintuitive but source-confirmed.
        callbacks[0xca] = clickOnly(0x4 | 0x8)
        callbacks[0xcb] = clickOnly(0x4)
        callbacks[0xcc] = clickOnly(0x1)
        callbacks[0xcd] = clickOnly(0)
        return callbacks
    }
}
