import Foundation

/// Native equivalent of Front_Menu_UpdateMousePosition in retail OpenLRR.
///
/// A scrolling MenuImage is taller than its 640 × 480 viewport. Cursor height
/// controls continuous scrolling: top edge moves toward the beginning,
/// bottom edge toward deeper missions; the 200–280px central band is neutral.
/// Frame rate is normalized to elapsed time (retail's formula used frames).
struct OriginalMenuScroll {
    private(set) var offsetY: Double = 0
    static let viewportHeight = 480.0

    mutating func reset() { offsetY = 0 }

    var isAtTop: Bool { offsetY >= -0.01 }

    func isAtBottom(imageHeight: Double) -> Bool {
        offsetY <= min(0, Self.viewportHeight - imageHeight) + 0.01
    }

    @discardableResult
    mutating func update(imageHeight: Double, canScroll: Bool,
                         mouseY: Double?, buttonsHeld: Bool,
                         elapsed: Double) -> Bool {
        let previous = offsetY
        guard canScroll, imageHeight.isFinite, imageHeight > Self.viewportHeight else {
            offsetY = 0
            return abs(previous - offsetY) > 0.001
        }
        guard let mouseY, mouseY.isFinite, mouseY >= 0, mouseY < 480,
              !buttonsHeld, elapsed.isFinite, elapsed > 0 else {
            return false
        }

        // Exact edge-response curve from FrontEnd.cpp: squared normalized
        // mouse distance times -STANDARD_FRAMERATE/100. The legacy frame
        // rate is 25 Hz, so multiply by 25 seconds^-1 here instead.
        if mouseY < 200 || mouseY > 280 {
            let fraction = mouseY * (100.0 / 480.0) - 50.0
            let distance = fraction * fraction * 0.02
            let direction = mouseY < 240 ? 1.0 : -1.0
            let velocity = distance * 0.25 * 25.0 * direction
            offsetY += velocity * min(elapsed, 1.0 / 10.0)
        }
        offsetY = min(0, max(Self.viewportHeight - imageHeight, offsetY))
        return abs(previous - offsetY) > 0.001
    }

    @discardableResult
    mutating func wheel(deltaY: Double, imageHeight: Double,
                        canScroll: Bool) -> Bool {
        let previous = offsetY
        guard canScroll, imageHeight.isFinite,
              imageHeight > Self.viewportHeight, deltaY.isFinite else {
            offsetY = 0
            return abs(previous - offsetY) > 0.001
        }
        offsetY = min(0, max(Self.viewportHeight - imageHeight,
                             offsetY + deltaY * 12.0))
        return abs(previous - offsetY) > 0.001
    }
}
