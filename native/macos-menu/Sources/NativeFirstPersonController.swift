import Foundation

/// First-person movement over the same conservative discovered-cavern
/// clearance used by clicked Raider routing. The original game's FP camera
/// tracks a selected object (Game.cpp::Lego_SetViewMode / Camera.cpp::Camera_Update).
/// Speeds and key bindings are provisional, not retail-verified.
struct NativeFirstPersonController {
    let navigation: NativeLevelNavigation
    private(set) var position: NativeLevelNavigation.Point
    private(set) var heading: Double

    static let provisionalSpeed = 2.5 // tiles/second, awaiting retail timing
    static let provisionalTurnRate = 2.4 // radians/second

    init?(navigation: NativeLevelNavigation, position: NativeLevelNavigation.Point, heading: Double) {
        guard heading.isFinite,
              navigation.segmentIsClear(from: position, to: position) else { return nil }
        self.navigation = navigation
        self.position = position
        self.heading = heading
    }

    /// Advance at most 100 ms after a pause; never teleport through a wall.
    /// A blocked diagonal tries one axis at a time to slide along a wall.
    /// Returns whether the Raider changed position (turning alone is not motion).
    @discardableResult
    mutating func advance(forward: Double, turn: Double, elapsed: Double,
                          obstacles: [NativeDynamicCollision.Disc] = []) -> Bool {
        guard elapsed.isFinite, elapsed > 0,
              forward.isFinite, turn.isFinite else { return false }
        let dt = min(elapsed, 0.1)
        let turnInput = max(-1, min(1, turn))
        heading += turnInput * Self.provisionalTurnRate * dt
        heading = atan2(sin(heading), cos(heading))
        let distance = max(-1, min(1, forward)) * Self.provisionalSpeed * dt
        guard abs(distance) > 1e-9 else { return false }
        let start = position
        // The terrain sweep alone cannot stop another moving Raider. Test
        // the same attempted segment against live OL Raider positions.
        func isClear(_ from: NativeLevelNavigation.Point,
                     _ to: NativeLevelNavigation.Point) -> Bool {
            navigation.segmentIsClear(from: from, to: to) &&
            NativeDynamicCollision.sweepIsClear(
                from: .init(x: from.x, y: from.y),
                to: .init(x: to.x, y: to.y), obstacles: obstacles)
        }
        let goal = NativeLevelNavigation.Point(
            x: start.x + sin(heading) * distance,
            y: start.y + cos(heading) * distance)
        if isClear(start, goal) {
            position = goal
            return true
        }
        let xOnly = NativeLevelNavigation.Point(x: goal.x, y: start.y)
        if isClear(start, xOnly) {
            position = xOnly
        }
        let yOnly = NativeLevelNavigation.Point(x: position.x, y: goal.y)
        if isClear(position, yOnly) {
            position = yOnly
        }
        return position != start
    }
}
