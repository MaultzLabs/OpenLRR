import Foundation

/// The original tutorial input restrictions from
/// src/openlrr/game/mission/NERPsFile.h (TutorialFlags).
/// NERPs' ClickOnly* actions apply these flags to the gameplay input layer.
/// Keep this independent of AppKit so the original integer masks can be tested
/// on Linux before they are used by the native 2D and SceneKit views.
struct NativeTutorialInputPolicy {
    static let allRestrictions: UInt32 = 0x1fff
    static let noIcons: UInt32 = 0x1
    static let noBlockAction: UInt32 = 0x2
    static let noMap: UInt32 = 0x4
    static let noObjects: UInt32 = 0x8
    static let noCamera: UInt32 = 0x1000

    let flags: UInt32

    init(flags: Int32) {
        self.flags = UInt32(bitPattern: flags)
    }

    static let unrestricted = NativeTutorialInputPolicy(flags: 0)

    var canClickMap: Bool { flags & Self.noMap == 0 }
    var canSelectObjects: Bool { flags & Self.noObjects == 0 }
    var canMoveCamera: Bool { flags & Self.noCamera == 0 }
    var canClickIcons: Bool { flags & Self.noIcons == 0 }

    /// Follow the source exactly, including its unusual subtraction rather
    /// than OR/AND arithmetic:
    /// ClickOnlyObjects = ALL & ~(NOMAP | NOOBJECTS) - allowCameraMovement
    /// ClickOnlyMap = ALL & ~NOMAP - allowCameraMovement
    /// ClickOnlyIcon = ALL & ~NOICONS - allowCameraMovement
    /// DisallowAll = ALL - allowCameraMovement
    /// The subtraction matches NERPFunc__ClickOnly* / DisallowAll in
    /// NERPsFunctions.cpp. The caller supplies the pre-shifted flag.
    static func scriptMask(kind: ScriptClickMode,
                           allowCameraMovementMask: UInt32) -> Int32 {
        let exceptions: UInt32
        switch kind {
        case .objects: exceptions = noMap | noObjects
        case .map: exceptions = noMap
        case .icons: exceptions = noIcons
        case .none: exceptions = 0
        }
        return Int32(bitPattern:
            (allRestrictions & ~exceptions) &- allowCameraMovementMask)
    }

    enum ScriptClickMode {
        case objects, map, icons, none
    }
}
