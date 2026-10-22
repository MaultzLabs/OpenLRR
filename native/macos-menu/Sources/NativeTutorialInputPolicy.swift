import Foundation

/// Input permissions used by the original NERPs tutorial scripts.
///
/// The bit values are transcribed from:
/// src/openlrr/game/mission/NERPsFile.h::TutorialFlags.
/// A bit means the corresponding game input is DISABLED, not enabled.
/// No script is equivalent to a zero mask (all normal inputs permitted).
struct NativeTutorialInputPolicy {
    enum Input {
        case icon, blockAction, map, object, radar, options, priorities
        case callToArms, information, multiSelect, cycleUnits, help, camera
    }

    static let allDisabledMask: UInt32 = 0x1fff
    static let unrestricted = NativeTutorialInputPolicy(flags: 0)

    let disabledMask: UInt32

    init(flags: Int32) {
        // Mask unknown bits. The original enum has precisely 13 controls.
        self.disabledMask = UInt32(bitPattern: flags) & Self.allDisabledMask
    }

    func permits(_ input: Input) -> Bool {
        let bit: UInt32
        switch input {
        case .icon: bit = 0x1
        case .blockAction: bit = 0x2
        case .map: bit = 0x4
        case .object: bit = 0x8
        case .radar: bit = 0x10
        case .options: bit = 0x20
        case .priorities: bit = 0x40
        case .callToArms: bit = 0x80
        case .information: bit = 0x100
        case .multiSelect: bit = 0x200
        case .cycleUnits: bit = 0x400
        case .help: bit = 0x800
        case .camera: bit = 0x1000
        }
        return (disabledMask & bit) == 0
    }
}
