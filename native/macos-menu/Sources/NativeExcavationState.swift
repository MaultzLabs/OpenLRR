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
    private(set) var revealed: Set<Position> = []
    private(set) var rubble: Set<Position> = []

    init(world: LevelWorld) {
        self.world = world
    }

    func tile(x: Int, y: Int) -> LevelWorld.Tile? {
        guard let original = world.tile(x: x, y: y) else { return nil }
        if excavated.contains(Position(x: x, y: y)) {
            return LevelWorld.Tile(x: x, y: y, terrainCode: 0,
                                   predugCode: 1, heightCode: original.heightCode)
        }
        if revealed.contains(Position(x: x, y: y)) {
            return LevelWorld.Tile(x: x, y: y, terrainCode: original.terrainCode,
                predugCode: original.excavation == .hiddenSlugHole ? 3 : 1, heightCode: original.heightCode)
        }
        return original
    }

    func tutorialGroundValue(_ id: Int32) -> Int32 {
        // NERPsRuntime_TutorialActionCallback adds BLOCK1_FLOOR (8),
        // not 1, for each marked exposed floor. Read the live drill overlay.
        world.tutorialBlocks(id).reduce(Int32(0)) { total, position in
            total &+ ((tile(x: position.x, y: position.y)?.excavation.isDiscoveredCavern == true) ? 8 : 0)
        }
    }

    func canDrill(_ wall: Position) -> Bool {
        guard !excavated.contains(wall),
              let tile = world.tile(x: wall.x, y: wall.y),
              tile.excavation == .wall,
              tile.terrain.isMineableWall, tile.terrain != .hard else { return false }
        return true
    }

    /// Find the shortest existing cavern route to a wall face. Never route
    /// through the solid target or diagonally across a corner.
    func plan(from raider: Position, wall: Position) -> DrillOrder? {
        guard canDrill(wall) else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated, revealed: revealed)
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
              NativeLevelNavigation(world: world, excavated: excavated, revealed: revealed).canWalk(raiderAt)
        else { return false }
        excavated.insert(order.wall)
        rubble.insert(order.wall)
        // Level_DestroyWall / Level_UncoverHiddenCavern traverse all eight
        // neighbours. Only original hidden cavern cells propagate discovery.
        var queue = [order.wall]
        var cursor = 0
        while cursor < queue.count {
            let p = queue[cursor]; cursor += 1
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let next = Position(x: p.x + dx, y: p.y + dy)
                    guard let t = world.tile(x: next.x, y: next.y),
                          t.excavation == .hidden || t.excavation == .hiddenSlugHole,
                          revealed.insert(next).inserted else { continue }
                    queue.append(next)
                }
            }
        }
        return true
    }
}
