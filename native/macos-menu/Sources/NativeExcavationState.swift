import Foundation

/// A mission-local overlay for the first real terrain-changing gameplay
/// operation. Original WWAD/MAP bytes are never changed or saved.
/// Drilling removes an already-visible, mineable wall only after a Raider has
/// reached a cardinally adjacent walkable tile. Resource drops, rubble,
/// stamina and drill speed are not yet simulated; this is a bounded prototype.
final class NativeExcavationState {
    typealias Position = NativeLevelNavigation.Position

    struct DrillOrder {
        let wall: Position
        let approach: Position
        let route: [Position]
    }

    let world: LevelWorld
    private(set) var excavated: Set<Position> = []

    init(world: LevelWorld) {
        self.world = world
    }

    func tile(x: Int, y: Int) -> LevelWorld.Tile? {
        guard let original = world.tile(x: x, y: y) else { return nil }
        if excavated.contains(Position(x: x, y: y)) {
            return LevelWorld.Tile(x: x, y: y, terrainCode: 0,
                                   predugCode: 1, heightCode: original.heightCode)
        }
        return original
    }

    func canDrill(_ wall: Position) -> Bool {
        guard !excavated.contains(wall),
              let tile = world.tile(x: wall.x, y: wall.y),
              tile.excavation == .wall,
              tile.terrain.isMineableWall else { return false }
        return true
    }

    /// Find the shortest existing cavern route to a wall face. Never route
    /// through the solid target or diagonally across a corner.
    func plan(from raider: Position, wall: Position) -> DrillOrder? {
        guard canDrill(wall) else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated)
        let candidates = [
            Position(x: wall.x, y: wall.y - 1),
            Position(x: wall.x + 1, y: wall.y),
            Position(x: wall.x, y: wall.y + 1),
            Position(x: wall.x - 1, y: wall.y)
        ]
        var best: DrillOrder?
        for approach in candidates {
            guard let route = nav.route(from: raider, to: approach),
                  route.count <= 512 else { continue }
            if best == nil || route.count < best!.route.count {
                best = DrillOrder(wall: wall, approach: approach, route: route)
            }
        }
        return best
    }

    /// Called once a unit finishes its approach. Revalidate against the
    /// current world to reject stale orders and impossible remote excavation.
    @discardableResult
    func finish(_ order: DrillOrder, raiderAt: Position) -> Bool {
        guard raiderAt == order.approach,
              abs(order.wall.x - raiderAt.x) + abs(order.wall.y - raiderAt.y) == 1,
              canDrill(order.wall),
              NativeLevelNavigation(world: world, excavated: excavated).canWalk(raiderAt)
        else { return false }
        excavated.insert(order.wall)
        return true
    }
}
