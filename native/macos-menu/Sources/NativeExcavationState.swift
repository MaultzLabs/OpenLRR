import Foundation

/// One-shot original animation work advances on unpaused mission frames, not
/// wall-clock completion handlers. Pending resource actions neither remove
/// drops nor credit NERPs until their final validated frame.
struct NativeResourceAnimationClock {
    let duration: Double
    private(set) var progress = 0.0

    init?(duration: Double) {
        guard duration.isFinite, duration > 0 else { return nil }
        self.duration = duration
    }

    mutating func advance(elapsed: Double) -> Bool {
        guard elapsed.isFinite, elapsed > 0 else { return false }
        // Like original drill work, bound an unobserved frame stall.
        progress = min(duration, progress + min(elapsed, 0.25))
        return progress >= duration
    }
}

/// A mission-local overlay for the first real terrain-changing gameplay
/// operation. Original WWAD/MAP bytes are never changed or saved.
/// Drilling removes an already-visible, mineable wall only after a Raider has
/// reached a cardinally adjacent walkable tile. Four-layer rubble/spade
/// clearance now follows; CryOreMap-derived dropped resources are tracked
/// separately from unported collection/storage, tools and stamina.
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
    // The original engine tracks four rubble layers (LEGO_RUBBLELAYERCOUNT).
    // Keep both retail MAP rubble and newly drilled rubble in the same
    // mission-local overlay; never change the source MAP.
    private(set) var rubbleLayers: [Position: Int] = [:]
    private(set) var clearWork: [Position: Double] = [:]
    private var clearedOriginalRubble: Set<Position> = []
    var rubble: Set<Position> { Set(rubbleLayers.keys) }
    // Original Level_Block_Damage accumulates work on the wall, not on the
    // current Raider action. Cancelling or retargeting must not heal the rock.
    // This normalized level-zero progress is mission-local; upgrades and
    // damage from other tools still require retail parity testing.
    private(set) var drillDamage: [Position: Double] = [:]
    /// Wall destruction creates a mission-only resource drop. Keep the
    /// original count and upgrade level; never credit NERPs picked-up/stored
    /// counters merely because a wall was opened.
    private(set) var resourceDrops: [Position: LevelWorld.CryOreDeposit] = [:]

    /// Original AITask_Type_Collect and AITask_Type_Deposit move one physical
    /// ore/crystal item at a time. The carried item is not stored inventory.
    struct ResourceUnit: Hashable {
        let kind: LevelWorld.CryOreDeposit.Kind
        let level: Int
    }

    struct CollectOrder {
        let tile: Position
        let route: [Position]
    }

    struct DepositOrder {
        let store: Position
        let approach: Position
        let route: [Position]
    }

    private let originalToolStores: Set<Position>
    private(set) var carrying: [String: ResourceUnit] = [:]
    private(set) var storedResources: [ResourceUnit: Int] = [:]
    // Retail Object.cpp increments picked-up counts on completed GatherRock.
    // Native Collect currently completes at confirmed arrival, before the
    // original GatherRock animation timing is implemented.
    private(set) var crystalsPickedUp: Int32 = 0
    private(set) var orePickedUp: Int32 = 0

    func pickedUpCount(_ kind: LevelWorld.CryOreDeposit.Kind) -> Int32 {
        kind == .crystal ? crystalsPickedUp : orePickedUp
    }

    /// Stored means physically deposited at a genuine original Toolstation.
    /// Other original resource sources/consumption remain unimplemented.
    func storedCount(_ kind: LevelWorld.CryOreDeposit.Kind) -> Int32 {
        let total: Int = storedResources.reduce(into: 0) { sum, entry in
            if entry.key.kind == kind { sum += entry.value }
        }
        return Int32(clamping: total)
    }

    init(world: LevelWorld, originalToolStores: Set<Position> = []) {
        self.originalToolStores = Set(originalToolStores.filter {
            (0..<world.width).contains($0.x) && (0..<world.height).contains($0.y)
        })
        self.world = world
        for y in 0..<world.height {
            for x in 0..<world.width {
                if let tile = world.tile(x: x, y: y),
                   tile.terrain == .rubble, tile.excavation.isDiscoveredCavern {
                    rubbleLayers[Position(x: x, y: y)] = 4
                }
            }
        }
    }

    /// Collect only exposed, reachable original dropped resources. The
    /// movement callback must revalidate at arrival; a planned route never
    /// reserves the stack or invents a successful pickup.
    func planCollect(from raider: Position, tile: Position, raiderID: String) -> CollectOrder? {
        guard !raiderID.isEmpty, carrying[raiderID] == nil,
              (resourceDrops[tile]?.count ?? 0) > 0,
              let route = NativeLevelNavigation(world: world, excavated: excavated,
                  revealed: revealed).route(from: raider, to: tile),
              route.count <= 512 else { return nil }
        return CollectOrder(tile: tile, route: route)
    }

    /// Consume exactly ONE item after confirmed arrival at its source tile.
    /// The retail source MAP bytes are unchanged, and this does not increment
    /// NERPs delivered/stored counters.
    @discardableResult
    func collect(_ order: CollectOrder, raiderID: String, raiderAt: Position) -> ResourceUnit? {
        guard !raiderID.isEmpty, carrying[raiderID] == nil,
              raiderAt == order.tile,
              NativeLevelNavigation(world: world, excavated: excavated,
                                    revealed: revealed).canWalk(raiderAt),
              let drop = resourceDrops[order.tile], drop.count > 0 else { return nil }
        let item = ResourceUnit(kind: drop.kind, level: drop.level)
        if drop.count == 1 { resourceDrops.removeValue(forKey: order.tile) }
        else {
            resourceDrops[order.tile] = .init(kind: drop.kind, level: drop.level,
                                              count: drop.count - 1)
        }
        carrying[raiderID] = item
        if item.kind == .crystal { crystalsPickedUp &+= 1 }
        else { orePickedUp &+= 1 }
        return item
    }

    /// A delivery destination must be a real original OL Toolstation.
    /// Its occupied footprint is not traversed. Use a reachable cardinal
    /// approach and preserve the real Raider's carrying state until arrival.
    func planDeposit(from raider: Position, raiderID: String,
                     blockedBuildings: Set<Position> = []) -> DepositOrder? {
        guard !raiderID.isEmpty, carrying[raiderID] != nil else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated,
            revealed: revealed, blockedBuildingTiles: blockedBuildings)
        var best: DepositOrder?
        for store in originalToolStores {
            for tile in [Position(x: store.x - 1, y: store.y),
                         Position(x: store.x + 1, y: store.y),
                         Position(x: store.x, y: store.y - 1),
                         Position(x: store.x, y: store.y + 1)] {
                guard let route = nav.route(from: raider, to: tile),
                      route.count <= 512 else { continue }
                if best == nil || route.count < best!.route.count {
                    best = DepositOrder(store: store, approach: tile, route: route)
                }
            }
        }
        return best
    }

    /// An unrelated building or a remote order never credits inventory.
    /// This is a mission-local native stored counter, NOT yet an original
    /// Building_Deposit or NERPs resource callback.
    @discardableResult
    func deposit(_ order: DepositOrder, raiderID: String, raiderAt: Position) -> ResourceUnit? {
        guard !raiderID.isEmpty, originalToolStores.contains(order.store),
              raiderAt == order.approach,
              abs(raiderAt.x - order.store.x) + abs(raiderAt.y - order.store.y) == 1,
              NativeLevelNavigation(world: world, excavated: excavated,
                                    revealed: revealed).canWalk(raiderAt),
              let item = carrying.removeValue(forKey: raiderID) else { return nil }
        storedResources[item, default: 0] += 1
        return item
    }

    func tile(x: Int, y: Int) -> LevelWorld.Tile? {
        guard let original = world.tile(x: x, y: y) else { return nil }
        if excavated.contains(Position(x: x, y: y)) {
            return LevelWorld.Tile(x: x, y: y, terrainCode: 0,
                                   predugCode: 1, heightCode: original.heightCode)
        }
        if clearedOriginalRubble.contains(Position(x: x, y: y)) {
            return LevelWorld.Tile(x: x, y: y, terrainCode: 0,
                                   predugCode: original.predugCode, heightCode: original.heightCode)
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

    struct ClearOrder {
        let tile: Position
        let route: [Position]
    }

    func canClearRubble(_ tile: Position) -> Bool {
        guard (rubbleLayers[tile] ?? 0) > 0 else { return false }
        return NativeLevelNavigation(world: world, excavated: excavated, revealed: revealed).canWalk(tile)
    }

    /// A Spade/Clear task targets walkable rubble itself, not the wall's old
    /// drilling face. Routing remains bounded to the discovered cavern.
    func planClear(from raider: Position, tile: Position) -> ClearOrder? {
        guard canClearRubble(tile),
              let route = NativeLevelNavigation(world: world, excavated: excavated,
                  revealed: revealed).route(from: raider, to: tile),
              route.count <= 512 else { return nil }
        return ClearOrder(tile: tile, route: route)
    }

    func validClear(_ order: ClearOrder, raiderAt: Position) -> Bool {
        raiderAt == order.tile && canClearRubble(order.tile)
    }

    /// Advance one of four original rubble layers per completed Clear cycle.
    /// Partial work is retained across interruptions, but never credited from
    /// remote or invalid/paused-time orders. A true return means all layers
    /// have been cleared; callers can also observe intermediate layer changes.
    @discardableResult
    func applyClear(_ order: ClearOrder, raiderAt: Position,
                    elapsedSeconds: Double, secondsPerLayer: Double) -> Bool {
        guard validClear(order, raiderAt: raiderAt),
              elapsedSeconds.isFinite, elapsedSeconds > 0,
              secondsPerLayer.isFinite, secondsPerLayer > 0 else { return false }
        let work = min(1.0, elapsedSeconds / secondsPerLayer)
        guard work.isFinite, work > 0 else { return false }
        let total = (clearWork[order.tile] ?? 0) + work
        if total < 1.0 {
            clearWork[order.tile] = total
            return false
        }
        // A frame can finish a layer with a fractional cycle left over.
        // Preserve that carried work on the NEXT layer rather than losing it
        // every time a visual rubble texture changes, making clear speed
        // sensitive to the app's frame rate. The per-frame contribution is
        // capped to at most one layer by the guard above.
        let remainder = max(0, total - 1.0)
        let remaining = (rubbleLayers[order.tile] ?? 0) - 1
        if remaining > 0 {
            rubbleLayers[order.tile] = remaining
            if remainder > 0 { clearWork[order.tile] = remainder }
            else { clearWork.removeValue(forKey: order.tile) }
            return false
        }
        clearWork.removeValue(forKey: order.tile)
        rubbleLayers.removeValue(forKey: order.tile)
        if world.tile(x: order.tile.x, y: order.tile.y)?.terrain == .rubble {
            clearedOriginalRubble.insert(order.tile)
        }
        return true
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

    /// Like Level_Block_Damage, partial digging is attached to the original
    /// wall position and survives interrupted orders. One second contributes
    /// 1 / configured drill-seconds, rather than resetting each ACT cycle.
    /// Never charge damage from a remote or stale order, a paused frame, or
    /// nonfinite/zero time. Call once per actual unpaused simulation frame.
    @discardableResult
    func applyDrill(_ order: DrillOrder, raiderAt: Position,
                    elapsedSeconds: Double, requiredSeconds: Double) -> Bool {
        guard validDrillFace(order, raiderAt: raiderAt),
              elapsedSeconds.isFinite, elapsedSeconds > 0,
              requiredSeconds.isFinite, requiredSeconds > 0 else { return false }
        let contribution = min(1.0, elapsedSeconds / requiredSeconds)
        guard contribution.isFinite, contribution > 0 else { return false }
        let completed = min(1.0, (drillDamage[order.wall] ?? 0) + contribution)
        if completed < 1.0 {
            drillDamage[order.wall] = completed
            return false
        }
        return finish(order, raiderAt: raiderAt)
    }

    func validDrillFace(_ order: DrillOrder, raiderAt: Position) -> Bool {
        raiderAt == order.approach &&
        abs(order.wall.x - raiderAt.x) + abs(order.wall.y - raiderAt.y) == 1 &&
        canDrill(order.wall) &&
        NativeLevelNavigation(world: world, excavated: excavated, revealed: revealed).canWalk(raiderAt)
    }

    /// Revalidate against the current map before revealing the wall. Retain
    /// this completion entry point for existing excavation/test callers.
    @discardableResult
    func finish(_ order: DrillOrder, raiderAt: Position) -> Bool {
        guard validDrillFace(order, raiderAt: raiderAt) else { return false }
        drillDamage.removeValue(forKey: order.wall)
        excavated.insert(order.wall)
        rubbleLayers[order.wall] = 4
        if let deposit = world.cryOreDeposit(x: order.wall.x, y: order.wall.y) {
            resourceDrops[order.wall] = deposit
        }
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
