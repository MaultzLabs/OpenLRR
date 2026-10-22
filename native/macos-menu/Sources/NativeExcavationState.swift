import Foundation

/// Mutable *session-only* excavation state over read-only retail MAP tiles.
/// Nothing is written back to the WAD or a save file. This is a limited
/// gameplay bridge: it does not simulate drilling duration, tool levels,
/// energy crystals, ore, rubble, reveal propagation or NERPs events.
final class NativeExcavationState {
    typealias Position = NativeLevelNavigation.Position

    enum DigResult: Equatable {
        case dug
        case outsideMap
        case blocked
        case notAdjacent
        case noStandingRoom
    }

    let world: LevelWorld
    private(set) var opened: Set<Position> = []

    init(world: LevelWorld) {
        self.world = world
    }

    func excavation(at point: Position) -> LevelWorld.Excavation? {
        guard let tile = world.tile(x: point.x, y: point.y) else { return nil }
        return opened.contains(point) ? .exposed : tile.excavation
    }

    func terrain(at point: Position) -> LevelWorld.Terrain? {
        guard let tile = world.tile(x: point.x, y: point.y) else { return nil }
        return opened.contains(point) ? .tunnel : tile.terrain
    }

    func canWalk(_ point: Position) -> Bool {
        guard excavation(at: point)?.isDiscoveredCavern == true,
              let terrain = terrain(at: point) else { return false }
        return !terrain.isLiquid
    }

    func canTarget(_ point: Position) -> Bool {
        guard let tile = world.tile(x: point.x, y: point.y),
              !opened.contains(point) else { return false }
        // Only a genuine undug wall can be excavated. Hidden original
        // caverns and other special predug states need retail reveal logic.
        return tile.excavation == .wall && tile.terrain.isMineableWall
    }

    /// A Raider must stand in a discovered, walkable cardinal neighbour
    /// at completion. This prevents tunnelling through unreachable walls.
    @discardableResult
    func dig(at target: Position, from raider: Position) -> DigResult {
        guard world.tile(x: target.x, y: target.y) != nil else {
            return .outsideMap
        }
        guard canTarget(target) else { return .blocked }
        guard abs(target.x - raider.x) + abs(target.y - raider.y) == 1 else {
            return .notAdjacent
        }
        guard canWalk(raider) else { return .noStandingRoom }
        opened.insert(target)
        return .dug
    }
}
