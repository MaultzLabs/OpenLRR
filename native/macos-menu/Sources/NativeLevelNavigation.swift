import Foundation

/// Bounded four-neighbour movement route over the original retail PredugMap.
///
/// This is the initial native Rock Raider movement *prototype*, deliberately
/// conservative: only already discovered caverns may be traversed, and lava
/// or water is never treated as walkable. It does not yet perform the retail
/// game's AI/routing, drilling, rubble clearing or vehicle navigation.
struct NativeLevelNavigation {
    struct Position: Hashable {
        let x: Int
        let y: Int
    }

    let world: LevelWorld
    let maximumTiles: Int
    /// Temporary mission-local excavation; the installed PredugMap stays read-only.
    let excavated: Set<Position>

    init(world: LevelWorld, excavated: Set<Position> = [],
         maximumTiles: Int = 150_000) {
        self.world = world
        self.excavated = excavated
        self.maximumTiles = maximumTiles
    }

    func canWalk(_ point: Position) -> Bool {
        guard let tile = world.tile(x: point.x, y: point.y) else { return false }
        if excavated.contains(point) {
            return tile.excavation == .wall && tile.terrain.isMineableWall
        }
        return tile.excavation.isDiscoveredCavern && !tile.terrain.isLiquid
    }

    /// Returns inclusive start-to-target tile positions, or nil if either
    /// endpoint is blocked, the destination is unreachable, or the map is
    /// too large to safely route. Does not modify the original level state.
    func route(from start: Position, to goal: Position) -> [Position]? {
        guard canWalk(start), canWalk(goal),
              world.width > 0, world.height > 0,
              world.width <= maximumTiles,
              world.height <= maximumTiles / world.width else {
            return nil
        }
        if start == goal { return [start] }

        let width = world.width
        let count = width * world.height
        func index(_ point: Position) -> Int { point.y * width + point.x }
        func point(_ index: Int) -> Position {
            Position(x: index % width, y: index / width)
        }

        var previous = [Int32](repeating: -1, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(min(count, 4096))
        let first = index(start)
        let last = index(goal)
        previous[first] = Int32(first)
        queue.append(first)

        var cursor = 0
        while cursor < queue.count {
            let here = queue[cursor]
            cursor += 1
            let location = point(here)
            // Four-way only: never allow diagonal corner clipping through rock.
            let neighbours = [
                Position(x: location.x, y: location.y - 1),
                Position(x: location.x + 1, y: location.y),
                Position(x: location.x, y: location.y + 1),
                Position(x: location.x - 1, y: location.y)
            ]
            for next in neighbours where canWalk(next) {
                let indexNext = index(next)
                guard previous[indexNext] == -1 else { continue }
                previous[indexNext] = Int32(here)
                if indexNext == last {
                    var result: [Position] = [goal]
                    var trace = here
                    while trace != first {
                        result.append(point(trace))
                        trace = Int(previous[trace])
                    }
                    result.append(start)
                    return result.reversed()
                }
                queue.append(indexNext)
            }
        }
        return nil
    }
}
