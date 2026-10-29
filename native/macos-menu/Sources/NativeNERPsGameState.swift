import Foundation

/// Persistent, source-grounded mission state for the original NERPs VM.
/// IDs follow the retail NPL function table (RRU NERPs documentation);
/// effects follow src/openlrr/game/mission/NERPsFunctions.cpp and
/// NERPsRuntime_UpdateTimers in NERPsFile.cpp. No simulated units or resources.
final class NativeNERPsGameState {
    enum StateError: Error {
        case invalidElapsedTime
    }

    private(set) var digIconClicks: Int32 = 0
    private(set) var backIconClicks: Int32 = 0
    private(set) var buildIconClicks: Int32 = 0
    // Counts are click events, not successful excavations. Retail Get*IconClicked
    // does not consume its counter (NERPsFunctions.cpp).
    func reportDigIconClick() { digIconClicks &+= 1 }
    func reportBackIconClick() { backIconClicks &+= 1 }
    func reportBuildIconClick() { buildIconClicks &+= 1 }
    var isPaused = false
    let script: NERPsScript
    private(set) var registers = [Int32](repeating: 0, count: 8)
    private(set) var timers = [Float](repeating: 0, count: 4)
    // NERPFunc__GetObjectiveSwitch consumes the one-shot objective signal.
    // This is a script-visible latch, not an invented mission-completion UI.
    private(set) var objectiveSwitch: Int32 = 0
    private var initialBriefingDismissalReported = false
    /// Bind to the actual objective overlay, not the one-shot ObjectiveSwitch.
    /// NERPFunc__GetObjectiveShowing (retail NPL 0x32) queries Objective_IsShowing.
    /// No overlay attached means no objective is showing.
    var objectiveShowing: (() -> Bool)?
    private(set) var tutorialFlags: Int32 = 0
    /// Camera masks change when original ClickOnly* functions execute.
    private(set) var allowCameraMovementMask: UInt32 = 0
    private(set) var suppressMessageArrow = false
    var inputPolicy: NativeTutorialInputPolicy {
        NativeTutorialInputPolicy(flags: tutorialFlags)
    }
    // The native 3D view currently supports ONE selected original OL Pilot.
    // GetMiniFigureSelected must reflect an actual click, never a made-up
    // starting unit count from the map file.
    private(set) var selectedRockRaiderCount: Int32 = 0
    private(set) var completedTicks = 0
    // In retail NERPs, 0 permits messages; nonzero suppresses them.
    private(set) var messagePermit = true
    private(set) var messageText: String?
    private(set) var lastMessageNumber: Int32?
    private(set) var nextArrowDisabled = false
    // The retail interpreter's message history, acknowledgement counter and
    // message-control NPL functions are distinct from the current HUD text.
    // Message timing uses the original configured default or decoded sound duration.
    private(set) var messageNeedsAdvance = false
    private(set) var messageWait = false
    private(set) var acknowledgedMessageCount: UInt32 = 0
    private(set) var recentMessageNumbers: [Int32] = []
    private(set) var messageTimerValues: [Float] = [1000, 500, 4000]
    private(set) var messageTimer: Float = 0
    /// The platform player returns the decoded sample duration in seconds.
    /// Invoked only when a different sound is requested, never every VM tick.
    var tutorialGroundValue: ((Int32) -> Int32)?
    var gotoTutorialCamera: ((Int32) -> Void)?
    var cameraAtTutorial: ((Int32) -> Int32)?
    var rockRaidersOnLevel: (() -> Int32)?
    var playMessageSound: ((String) -> Double?)?
    private var lastSoundPath: String?
    private var randomState: UInt32 = 1
    private func nextRandom() -> Int32 {
        // engine/core/Random.cpp: original Microsoft C runtime generator.
        randomState = randomState &* 214013 &+ 2531011
        return Int32((randomState >> 16) & 0x7fff)
    }
    private let messages: NativeNERPsMessageFile?
    /// NERPsRuntime_UpdateTimers distinguishes tutorials with a Next button
    /// from text-only timed messages. The native mission overlay supplies
    /// a Next button, including a fallback when the original bitmap is absent.
    private let hasNextButton: Bool

    init(script: NERPsScript, messages: NativeNERPsMessageFile? = nil,
         hasNextButton: Bool = true) {
        self.script = script
        self.messages = messages
        self.hasNextButton = hasNextButton
    }

    /// Objective_StopShowing signals the initial briefing-to-play transition
    /// once. Call on user dismissal only, never when exiting the mission or
    /// merely detaching its view. Later BF/C0 script writes/reads remain free
    /// to manage their own latch; repeated UI callbacks must not re-arm it.
    @discardableResult
    func reportInitialBriefingDismissed() -> Bool {
        guard !initialBriefingDismissalReported else { return false }
        initialBriefingDismissalReported = true
        objectiveSwitch = 1
        return true
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
        // NERPsRuntime_UpdateTimers (NERPsFile.cpp): an enabled Next arrow
        // holds the timer until the user advances the current message.
        // Messages without Next, or with Next disabled by SetMessage's second
        // argument, instead count down using the original millisecond timer.
        if messageTimer > 0 {
            if hasNextButton && messageText != nil && !nextArrowDisabled {
                if !messageNeedsAdvance { messageTimer = 0 }
            } else {
                messageTimer = max(0, messageTimer - milliseconds)
            }
        }
    }

    /// Called only when a verified original message audio sample starts.
    /// Keeping this separate prevents inventing voice timings from text.
    func startOriginalMessageAudio(durationMilliseconds: Float) throws {
        guard durationMilliseconds.isFinite,
              durationMilliseconds >= 0, durationMilliseconds <= 600_000 else {
            throw StateError.invalidElapsedTime
        }
        messageTimer = durationMilliseconds
    }

    /// Corresponds to retail NERPsRuntime_AdvanceMessage in its normal
    /// (no-history-navigation) state: acknowledge once, not every VM tick.
    /// Script-level AdvanceMessage can call this even with a disabled arrow;
    /// the AppKit button below respects nextArrowDisabled separately.
    @discardableResult
    func advanceMessage() -> Bool {
        guard messageNeedsAdvance else { return false }
        messageNeedsAdvance = false
        acknowledgedMessageCount &+= 1
        return true
    }

    /// During the initial briefing the caller passes zero interface elapsed
    /// time, but still ticks NERPs (GameState.cpp). isPaused is the separate
    /// diagnostic VM pause, not the objective overlay's world-time pause.
    func tick(elapsedMilliseconds: Float, maxSteps: Int = 200_000,
              onCall: ((NERPsRuntime.Call) -> Void)? = nil) throws -> NERPsRuntime.Tick {
        guard !isPaused else {
            return NERPsRuntime.Tick(visitedInstructions: 0, functionCalls: 0,
                                    actionsExecuted: 0, stoppedByStopFunction: false)
        }
        try advanceTimers(milliseconds: elapsedMilliseconds)
        let result = try NERPsRuntime.run(script, functions: functions(),
                                          maxSteps: maxSteps, onCall: onCall)
        completedTicks += 1
        return result
    }

    /// Called by actual selection events in NativeLevel3DView, not from a
    /// simulated user or a placeholder mission.
    func reportRockRaiderSelection(count: Int32) {
        selectedRockRaiderCount = max(0, count)
    }

    func reportRockRaiderSelection(_ selected: Bool) {
        selectedRockRaiderCount = selected ? 1 : 0
    }

    /// Only proven functions are available. If bytecode reaches another ID,
    /// NERPsRuntime throws rather than manufacturing gameplay outcomes.
    func functions() -> [Int: NERPsRuntime.Function] {
        var callbacks: [Int: NERPsRuntime.Function] = [:]
        callbacks[0x32] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in
            self.objectiveShowing?() == true ? 1 : 0
        })
        if let query = tutorialGroundValue {
            callbacks[0x72] = .init(kind: .expression(arity: 1), invoke: { query($0[0]) })
        }
        if let move = gotoTutorialCamera {
            callbacks[0x73] = .init(kind: .action(arity: 1), invoke: { move($0[0]); return 0 })
        }
        if let query = cameraAtTutorial {
            callbacks[0x8f] = .init(kind: .expression(arity: 1), invoke: { query($0[0]) })
        }
        if let count = rockRaidersOnLevel {
            callbacks[0x34] = .init(kind: .expression(arity: 0), invoke: { _ in count() })
        }
        callbacks[0] = .init(kind: .action(arity: 0), invoke: { _ in 0 }) // Stop
        callbacks[1] = .init(kind: .expression(arity: 0), invoke: { _ in 1 })
        callbacks[2] = .init(kind: .expression(arity: 0), invoke: { _ in 0 })
        callbacks[3] = .init(kind: .expression(arity: 0), invoke: { _ in 0 })
        callbacks[4] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.nextRandom() & 0xfff })
        callbacks[5] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.nextRandom() % 10 })
        callbacks[6] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.nextRandom() % 100 })
        callbacks[7] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.nextRandom() & 1 })
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
        // Original NPL 0x50: CountSelectedUnits_ByObjectName(PILOT).
        // Until multi-selection is ported this is the actual single
        // selected Rock Raider from the OL object and native viewport.
        callbacks[0x50] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in
            self.selectedRockRaiderCount
        })
        // Original NPL function IDs: SetMessagePermit and SetMessage.
        callbacks[0x31] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            let newPermit = args[0] != 0
            let changed = newPermit != self.messagePermit
            self.messagePermit = newPermit
            self.messageText = nil
            // A script can execute SetMessagePermit(0) and the same
            // SetMessage on *every* frame. Repeated permit values must
            // not manufacture another player acknowledgement after Next.
            if changed {
                self.lastMessageNumber = nil
                self.messageNeedsAdvance = false
            }
            return args[0]
        })
        callbacks[0x10] = .init(kind: .action(arity: 2),
                                invoke: { [unowned self] args in
            guard !self.messagePermit else { return 0 }
            // Retail normalizes zero and one to the same first line.
            let number = args[0] == 0 ? 1 : args[0]
            let isNew = self.lastMessageNumber != number
            self.lastMessageNumber = number
            self.messageText = self.messages?.text(for: args[0])
            self.nextArrowDisabled = args[1] != 0
            // A repeated SetMessage on each script update must not
            // re-arm the already-acknowledged Next button.
            if isNew, self.messageText != nil {
                // NERPs_Level_NERPMessage_Parse starts with timerValues[2],
                // then uses sampleSeconds * timerValues[0] + timerValues[1].
                self.messageTimer = self.messageTimerValues[2]
                for path in self.messages?.soundPaths(for: number) ?? [] {
                    guard path.lowercased() != self.lastSoundPath else { continue }
                    if let seconds = self.playMessageSound?(path), seconds.isFinite,
                       seconds >= 0, seconds <= 600 {
                        self.lastSoundPath = path.lowercased()
                        self.messageTimer = Float(seconds) * self.messageTimerValues[0] + self.messageTimerValues[1]
                    }
                }
                if self.recentMessageNumbers.last != args[0] {
                    self.recentMessageNumbers.append(args[0])
                    if self.recentMessageNumbers.count > 8 {
                        self.recentMessageNumbers.removeFirst()
                    }
                }
                self.messageNeedsAdvance = true
            }
            return 0
        })
        // Original NPL table: SetMessageWait 0x58, GetMessageTimer 0x6B,
        // SetMessageTimerValues 0x6C, AdvanceMessage 0xC8 and
        // GetMessagesAreUpToDate 0xD1 (RRU NERPs function table).
        callbacks[0x58] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.messageWait = args[0] != 0
            // The original SetMessage blocks within a Windows message
            // loop when this is enabled. Our native app instead exposes
            // the wait state; blocking AppKit's run loop is not safe.
            return args[0]
        })
        callbacks[0x6b] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in
            Int32(min(Float(Int32.max - 256),
                      max(0, self.messageTimer)))
        })
        callbacks[0x6c] = .init(kind: .action(arity: 3),
                                invoke: { [unowned self] args in
            self.messageTimerValues = args.map {
                Float(UInt32(bitPattern: $0))
            }
            return 1
        })
        callbacks[0xc8] = .init(kind: .action(arity: 0),
                                invoke: { [unowned self] _ in
            self.advanceMessage()
            return 0
        })
        callbacks[0xd1] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in
            let lines = self.messages?.lines.count ?? 0
            return self.acknowledgedMessageCount >= UInt32(lines) ? 1 : 0
        })
        // Retail NPL 0xC9–0xCE drive the tutorial's accepted inputs.
        // Preserve the original flags and camera-mask subtraction.
        callbacks[0xc9] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.allowCameraMovementMask = UInt32(bitPattern: args[0]) &<< 12
            return 0
        })
        callbacks[0xca] = .init(kind: .action(arity: 0),
                                invoke: { [unowned self] _ in
            self.tutorialFlags = NativeTutorialInputPolicy.scriptMask(
                kind: .objects, allowCameraMovementMask: self.allowCameraMovementMask)
            return 0
        })
        callbacks[0xcb] = .init(kind: .action(arity: 0),
                                invoke: { [unowned self] _ in
            self.tutorialFlags = NativeTutorialInputPolicy.scriptMask(
                kind: .map, allowCameraMovementMask: self.allowCameraMovementMask)
            return 0
        })
        callbacks[0xcc] = .init(kind: .action(arity: 0),
                                invoke: { [unowned self] _ in
            self.tutorialFlags = NativeTutorialInputPolicy.scriptMask(
                kind: .icons, allowCameraMovementMask: self.allowCameraMovementMask)
            return 0
        })
        callbacks[0xcd] = .init(kind: .action(arity: 0),
                                invoke: { [unowned self] _ in
            self.tutorialFlags = NativeTutorialInputPolicy.scriptMask(
                kind: .none, allowCameraMovementMask: self.allowCameraMovementMask)
            return 0
        })
        callbacks[0xce] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.suppressMessageArrow = args[0] != 0
            return 0
        })
        callbacks[0x5d] = .init(kind: .expression(arity: 0),
                                invoke: { [unowned self] _ in self.tutorialFlags })
        callbacks[0x5e] = .init(kind: .action(arity: 1),
                                invoke: { [unowned self] args in
            self.tutorialFlags = args[0]
            return self.tutorialFlags
        })
        // Original NPL table: Set/Get Dig (0x40/0x41), Back (0x3d/0x3e).
        // https://kb.rockraidersunited.com/NERPs_documentation
        callbacks[0x40] = .init(kind: .action(arity: 1), invoke: { [unowned self] args in
            self.digIconClicks = args[0]; return 0
        })
        callbacks[0x41] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.digIconClicks })
        callbacks[0x3d] = .init(kind: .action(arity: 1), invoke: { [unowned self] args in
            self.backIconClicks = args[0]; return 0
        })
        callbacks[0x3e] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.backIconClicks })
        callbacks[0x36] = .init(kind: .action(arity: 1), invoke: { [unowned self] args in
            self.buildIconClicks = args[0]; return 0
        })
        callbacks[0x35] = .init(kind: .expression(arity: 0), invoke: { [unowned self] _ in self.buildIconClicks })
        return callbacks
    }
}
