import Foundation

@main struct NativeTutorialInputPolicyTests {
    static func main() {
        let unbounded = NativeTutorialInputPolicy.unrestricted
        precondition(unbounded.permits(.object) && unbounded.permits(.map))
        precondition(unbounded.permits(.camera))

        // Retail NERPFunc__ClickOnlyObjects excludes NOMAP/NOOBJECTS from
        // TUTORIAL_FLAGS_ALL, meaning both map and object interaction remain enabled.
        let objectsOnly = NativeTutorialInputPolicy(flags: Int32(0x1fff & ~0xc))
        precondition(objectsOnly.permits(.object) && objectsOnly.permits(.map))
        precondition(!objectsOnly.permits(.icon) && !objectsOnly.permits(.radar))
        precondition(!objectsOnly.permits(.camera))

        // Retail NERPFunc__ClickOnlyMap permits only map targeting.
        let mapOnly = NativeTutorialInputPolicy(flags: Int32(0x1fff & ~0x4))
        precondition(mapOnly.permits(.map))
        precondition(!mapOnly.permits(.object))
        precondition(!mapOnly.permits(.camera))

        let completelyLocked = NativeTutorialInputPolicy(flags: 0x1fff)
        let inputs: [NativeTutorialInputPolicy.Input] = [
            .icon, .blockAction, .map, .object, .radar, .options,
            .priorities, .callToArms, .information, .multiSelect,
            .cycleUnits, .help, .camera
        ]
        precondition(inputs.allSatisfy { !completelyLocked.permits($0) })

        // The original AllowCameraMovement(1) clears bit 0x1000 when a
        // click-only restriction is next assigned.
        let cameraAllowed = NativeTutorialInputPolicy(flags: Int32(0x1fff & ~0x1004))
        precondition(cameraAllowed.permits(.map) && cameraAllowed.permits(.camera))
        precondition(!cameraAllowed.permits(.object))

        // Even malformed/negative signed masks cannot enable unknown controls.
        precondition(NativeTutorialInputPolicy(flags: -1).disabledMask == 0x1fff)
        precondition(NativeTutorialInputPolicy(flags: 0x4000).disabledMask == 0)

        print("PASS: source-grounded NERPs tutorial input restrictions")
    }
}
