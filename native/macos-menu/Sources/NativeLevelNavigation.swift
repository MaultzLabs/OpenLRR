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
    let excavated: Set<Position>
    let revealed: Set<Position>
    let blockedBuildingTiles: Set<Position>
    let maximumTiles: Int

    init(world: LevelWorld, excavated: Set<Position> = [], revealed: Set<Position> = [], blockedBuildingTiles: Set<Position> = [], maximumTiles: Int = 150_000) {
        self.world = world
        self.excavated = excavated
        self.revealed = revealed
        self.blockedBuildingTiles = blockedBuildingTiles
        self.maximumTiles = maximumTiles
    }

    func canWalk(_ point: Position) -> Bool {
        guard !blockedBuildingTiles.contains(point) else { return false }
        guard let tile = world.tile(x: point.x, y: point.y) else { return false }
        if excavated.contains(point) { return tile.terrain.isMineableWall }
        guard tile.excavation.isDiscoveredCavern || revealed.contains(point) else { return false }
        return !tile.terrain.isLiquid
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

extension NativeLevelNavigation {
    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    /// Conservative square footprint enclosing the current Raider capsule.
    /// Sweep the entire segment against expanded blocked tiles, not discrete
    /// samples: fast motion cannot tunnel through a wall or clip a corner.
    func segmentIsClear(from a: Point, to b: Point, clearance: Double = 0.23) -> Bool {
        guard clearance.isFinite, clearance > 0, clearance < 0.5,
              [a.x, a.y, b.x, b.y].allSatisfy({ $0.isFinite }),
              min(a.x, b.x) > clearance, min(a.y, b.y) > clearance,
              max(a.x, b.x) < Double(world.width) - clearance,
              max(a.y, b.y) < Double(world.height) - clearance else { return false }
        let left = Int(floor(min(a.x, b.x) - clearance))
        let right = Int(floor(max(a.x, b.x) + clearance))
        let top = Int(floor(min(a.y, b.y) - clearance))
        let bottom = Int(floor(max(a.y, b.y) + clearance))
        guard right - left + 1 <= maximumTiles,
              bottom - top + 1 <= maximumTiles / (right - left + 1) else { return false }
        for y in top...bottom {
            for x in left...right where !canWalk(Position(x: x, y: y)) {
                var enter = 0.0, leave = 1.0
                func intersectsAxis(_ start: Double, _ delta: Double,
                                    _ lo: Double, _ hi: Double) -> Bool {
                    if abs(delta) < 1e-12 { return start >= lo && start <= hi }
                    let t0 = (lo - start) / delta, t1 = (hi - start) / delta
                    enter = max(enter, min(t0, t1))
                    leave = min(leave, max(t0, t1))
                    return enter <= leave
                }
                if intersectsAxis(a.x, b.x - a.x, Double(x) - clearance, Double(x + 1) + clearance),
                   intersectsAxis(a.y, b.y - a.y, Double(y) - clearance, Double(y + 1) + clearance) {
                    return false
                }
            }
        }
        return true
    }

    /// Preserve the precise clicked endpoint. The tile route supplies a
    /// corridor; swept-clearance shortcuts remove unnecessary grid turns.
    /// Reject wall-adjacent targets where the Raider's body cannot fit.
    func continuousRoute(from start: Point, to goal: Point) -> [Point]? {
        guard segmentIsClear(from: start, to: start),
              segmentIsClear(from: goal, to: goal) else { return nil }
        if segmentIsClear(from: start, to: goal) { return [start, goal] }
        guard let tiles = route(from: Position(x: Int(floor(start.x)), y: Int(floor(start.y))),
                                to: Position(x: Int(floor(goal.x)), y: Int(floor(goal.y)))),
              tiles.count <= 512 else { return nil }
        let points = [start] + tiles.map { Point(x: Double($0.x) + 0.5, y: Double($0.y) + 0.5) } + [goal]
        var result = [start], cursor = 0
        while cursor < points.count - 1 {
            var next = points.count - 1
            while next > cursor && !segmentIsClear(from: points[cursor], to: points[next]) { next -= 1 }
            guard next > cursor else { return nil }
            result.append(points[next])
            cursor = next
        }
        return result
    }
}
