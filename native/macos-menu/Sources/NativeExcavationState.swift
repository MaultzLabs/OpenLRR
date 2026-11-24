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

/// First-person mode gives the player exclusive control of ONE Raider, not
/// ownership of the whole cavern. Keep other eligible workers on real
/// Collect/Deposit/Clear jobs while the local camera is attached to a Pilot.
enum NativeAutonomousWorkPolicy {
    static func busyRaiderIDs(manuallyHeld: Set<String>,
                              firstPersonRaider: String?) -> Set<String> {
        var busy = manuallyHeld
        if let firstPersonRaider { busy.insert(firstPersonRaider) }
        return busy
    }

    static func allowsCollectOrder(raiderID: String, continuingTask: Bool,
                                   firstPersonRaider: String?) -> Bool {
        guard let firstPersonRaider else { return true }
        // Scene interaction while in F-mode cannot create a manual Collect.
        // The scheduler may still use a DIFFERENT, genuinely idle Raider.
        return continuingTask && raiderID != firstPersonRaider
    }
}

/// A mission-local overlay for the first real terrain-changing gameplay
/// operation. Original WWAD/MAP bytes are never changed or saved.
/// Drilling removes an already-visible, mineable wall only after a Raider has
/// reached a cardinally adjacent walkable tile. Four-layer rubble/spade
/// clearance now follows; CryOreMap-derived dropped resources, one-piece
/// collecting, and Toolstation storage are tracked without modifying MAP/WAD.
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

    /// Existing OL PowerCrystal/Ore are physical source objects too. Preserve
    /// their author-specified IDs and per-object order; unlike CryOreMap walls
    /// these resources start in the cavern at their own fractional OL positions.
    /// ProcessedOre requires separate retail economics and is not counted here.
    private struct PlacedResource {
        let identifier: String
        let unit: ResourceUnit
        let x: Double
        let y: Double
    }
    private var placedResources: [Position: [PlacedResource]] = [:]
    private var pendingMapDrops: [Position: LevelWorld.CryOreDeposit] = [:]
    // Keep the original spawn size for stable per-object positions as the
    // currently rendered stack shrinks. Retail PTL tumble is not yet ported.
    private var mapDropSpawnCounts: [Position: Int] = [:]
    private var justCollectedOriginalIDs: [String: String] = [:]

    /// Return the exact original OL model consumed by the last verified
    /// Collect action. A failed, repeated or merely planned order has no ID.
    func takeCollectedOriginalPlacementID(raiderID: String) -> String? {
        justCollectedOriginalIDs.removeValue(forKey: raiderID)
    }

    func hasPlacedResource(at tile: Position) -> Bool {
        !(placedResources[tile]?.isEmpty ?? true)
    }

    /// Physical OL objects are not required to sit at tile centres. The
    /// continuous mover must reach the author's fractional position while
    /// collision and order validation still use the containing map tile.
    func collectDestination(at tile: Position) -> NativeLevelNavigation.Point {
        if let source = placedResources[tile]?.first {
            return .init(x: source.x, y: source.y)
        }
        if let point = mapDropPositions(at: tile).last { return point }
        return .init(x: Double(tile.x) + 0.5, y: Double(tile.y) + 0.5)
    }

    /// Shared ground-model and movement positions. The current grid is a
    /// provisional layout, not the original rockfall tumble animation. Keep
    /// the initial grid fixed and remove its last visible object on pickup.
    func mapDropPositions(at tile: Position) -> [NativeLevelNavigation.Point] {
        guard !hasPlacedResource(at: tile),
              let spawnCount = mapDropSpawnCounts[tile], spawnCount > 0,
              let remaining = resourceDrops[tile]?.count, remaining > 0,
              remaining <= spawnCount else { return [] }
        let columns = min(5, max(1, Int(ceil(sqrt(Double(spawnCount))))))
        let rows = Int(ceil(Double(spawnCount) / Double(columns)))
        return (0..<remaining).map { index in
            let column = index % columns
            let row = index / columns
            let offsetX = (Double(column) - Double(columns - 1) / 2.0) * 0.12
            let offsetY = (Double(row) - Double(rows - 1) / 2.0) * 0.12
            return NativeLevelNavigation.Point(x: Double(tile.x) + 0.5 + offsetX,
                                               y: Double(tile.y) + 0.5 + offsetY)
        }
    }

    /// Preserve exact authored OL targets. For provisional grid drops only,
    /// fall back to the same tile centre when the Pilot footprint cannot fit
    /// at the visible mesh. This keeps larger configured Pilots from getting
    /// stuck forever at an otherwise walkable drilled tile.
    func collectApproach(at tile: Position, clearance: Double,
                         blockedBuildings: Set<Position> = []) -> NativeLevelNavigation.Point {
        let target = collectDestination(at: tile)
        guard !hasPlacedResource(at: tile) else { return target }
        let nav = NativeLevelNavigation(world: world, excavated: excavated,
            revealed: revealed, blockedBuildingTiles: blockedBuildings)
        if nav.segmentIsClear(from: target, to: target, clearance: clearance) { return target }
        return .init(x: Double(tile.x) + 0.5, y: Double(tile.y) + 0.5)
    }

    /// A single visible pickup target is exposed at a time in the native
    /// scene. Do not send another Raider to the same physical object even
    /// if the underlying stack has more units than outstanding reservations.
    func pickupTargetAvailable(at tile: Position, for raiderID: String) -> Bool {
        !collectReservations.contains { $0.key != raiderID && $0.value == tile }
    }

    private func nextPlacedDeposit(at tile: Position) -> LevelWorld.CryOreDeposit? {
        guard let entries = placedResources[tile], let first = entries.first else { return nil }
        let count = entries.prefix {
            $0.unit.kind == first.unit.kind && $0.unit.level == first.unit.level
        }.count
        return .init(kind: first.unit.kind, level: first.unit.level, count: count)
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
    // Source AITask queues own individual resource objects. Until original
    // object-level task references are ported, reserve ONE unit of a real
    // CryOreMap stack per Raider, rather than locking the entire stack.
    // A planned route alone never consumes or creates an item.
    private(set) var collectReservations: [String: Position] = [:]

    private func availableCollectUnits(at tile: Position, for raiderID: String) -> Int {
        guard let drop = resourceDrops[tile] else { return 0 }
        let reservedForOthers = collectReservations.reduce(into: 0) { count, reservation in
            if reservation.key != raiderID && reservation.value == tile { count += 1 }
        }
        return max(0, drop.count - reservedForOthers)
    }

    /// Original AITask_Initialise starts Crystals at priority 55, while Ore
    /// and DefaultCollect retain the initial 49. Higher wins before route
    /// distance. The player-editable global AI priority system is not ported.
    private func collectPriority(at tile: Position) -> Int {
        resourceDrops[tile]?.kind == .crystal ? 55 : 49
    }

    @discardableResult
    func reserveCollect(tile: Position, raiderID: String) -> Bool {
        guard !raiderID.isEmpty, carrying[raiderID] == nil else { return false }
        if let existing = collectReservations[raiderID] { return existing == tile }
        guard availableCollectUnits(at: tile, for: raiderID) > 0 else { return false }
        collectReservations[raiderID] = tile
        return true
    }

    func releaseCollectReservation(raiderID: String) {
        collectReservations.removeValue(forKey: raiderID)
    }
    // Retail Object.cpp increments picked-up counts after the Collect activity.
    // NativeLevel3DView now calls collect only after an authored Collect
    // animation completes (or the explicitly provisional missing-clip fallback).
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

    init(world: LevelWorld, originalToolStores: Set<Position> = [],
         originalResourcePlacements: [OriginalObjectList.Placement] = []) {
        self.originalToolStores = Set(originalToolStores.filter {
            (0..<world.width).contains($0.x) && (0..<world.height).contains($0.y)
        })
        self.world = world
        for placement in originalResourcePlacements {
            let kind: LevelWorld.CryOreDeposit.Kind
            switch placement.type.lowercased() {
            case "powercrystal": kind = .crystal
            case "ore": kind = .ore
            default: continue
            }
            guard placement.x.isFinite, placement.y.isFinite,
                  placement.x >= 0, placement.y >= 0,
                  placement.x < Double(world.width), placement.y < Double(world.height) else { continue }
            let tile = Position(x: Int(floor(placement.x)), y: Int(floor(placement.y)))
            // An original OL object cannot be collected through solid rock.
            guard let original = world.tile(x: tile.x, y: tile.y),
                  original.excavation != .wall else { continue }
            placedResources[tile, default: []].append(
                PlacedResource(identifier: placement.identifier,
                               unit: ResourceUnit(kind: kind, level: 0),
                               x: placement.x, y: placement.y))
        }
        for tile in placedResources.keys {
            resourceDrops[tile] = nextPlacedDeposit(at: tile)
        }
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
    func planCollect(from raider: Position, tile: Position, raiderID: String,
                     blockedBuildings: Set<Position> = []) -> CollectOrder? {
        guard !raiderID.isEmpty, carrying[raiderID] == nil,
              availableCollectUnits(at: tile, for: raiderID) > 0,
              let route = NativeLevelNavigation(world: world, excavated: excavated,
                  revealed: revealed, blockedBuildingTiles: blockedBuildings)
                  .route(from: raider, to: tile),
              route.count <= 512 else { return nil }
        return CollectOrder(tile: tile, route: route)
    }

    /// After a completed deposit, continue the original Collect -> Deposit
    /// task chain with a still-exposed CryOreMap object. Honor the original
    /// initial Crystal(55) > Ore(49) task priority, then shortest route and
    /// row-major ties. Active automatic pickup targets may be excluded while
    /// our source-object positions are still approximated by tile centres.
    /// This does not reserve a drop or grant inventory.
    /// It must be re-planned and revalidated on actual arrival.
    func planNextCollect(from raider: Position, raiderID: String,
                         blockedBuildings: Set<Position> = [],
                         excludedTargets: Set<Position> = []) -> CollectOrder? {
        guard !raiderID.isEmpty, carrying[raiderID] == nil,
              collectReservations[raiderID] == nil else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated,
            revealed: revealed, blockedBuildingTiles: blockedBuildings)
        var best: CollectOrder?
        let candidates = resourceDrops.keys.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }
        for tile in candidates {
            // A follow-up job must not collide with another Raider's active
            // tile-centre Collect destination while stacked object positions
            // remain provisional. Manual per-unit Collect is unaffected.
            guard !excludedTargets.contains(tile),
                  availableCollectUnits(at: tile, for: raiderID) > 0,
                  let route = nav.route(from: raider, to: tile),
                  route.count <= 512 else { continue }
            if let current = best {
                let priority = collectPriority(at: tile)
                let previous = collectPriority(at: current.tile)
                guard priority > previous ||
                      (priority == previous && route.count < current.route.count) else {
                    continue
                }
            }
            best = CollectOrder(tile: tile, route: route)
        }
        return best
    }

    /// The original engine queues AITask_Type_Collect for exposed resources
    /// and assigns work to idle units. This is a bounded, mission-local first
    /// slice: only real unreserved dropped items with a reachable original
    /// Toolstation can be assigned. Initial retail resource priorities rank
    /// jobs before shortest route; assignment still grants no inventory.
    /// Original per-object AI task queues remain unported. `excludedTargets`
    /// prevents the provisional centre-of-tile mover from steering two idle
    /// workers into the same occupied pickup location simultaneously.
    struct IdleRaider {
        let identifier: String
        let tile: Position
    }

    struct IdleCollectAssignment {
        let raiderID: String
        let order: CollectOrder
    }

    func planIdleCollection(raiders: [IdleRaider], busyRaiderIDs: Set<String>,
                            blockedBuildings: Set<Position> = [],
                            excludedTargets: Set<Position> = []) -> IdleCollectAssignment? {
        guard !resourceDrops.isEmpty, !originalToolStores.isEmpty else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated,
            revealed: revealed, blockedBuildingTiles: blockedBuildings)
        let drops = resourceDrops.keys.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }
        let idle = raiders.sorted { $0.identifier < $1.identifier }
        var best: (priority: Int, cost: Int, raiderID: String, order: CollectOrder)?
        for raider in idle {
            guard !raider.identifier.isEmpty,
                  !busyRaiderIDs.contains(raider.identifier),
                  carrying[raider.identifier] == nil,
                  collectReservations[raider.identifier] == nil,
                  nav.canWalk(raider.tile) else { continue }
            for tile in drops {
                // Multiple workers may carry out separate Collect jobs, but
                // our tile-centre approach cannot physically accommodate two
                // Raiders arriving at the same stack simultaneously. Keep
                // outstanding Collect destinations for other Raiders out of
                // automatic planning; explicit player Collect still uses
                // independent per-unit ownership.
                guard !excludedTargets.contains(tile),
                      availableCollectUnits(at: tile, for: raider.identifier) > 0,
                      let pickupRoute = nav.route(from: raider.tile, to: tile),
                      pickupRoute.count <= 512 else { continue }

                // A collectible resource must also have a real reachable
                // delivery destination; an unbuilt or inaccessible Toolstation
                // must not cause an idle unit to pick up and strand an item.
                var deliveryLength: Int?
                for store in originalToolStores {
                    for entrance in [Position(x: store.x - 1, y: store.y),
                                     Position(x: store.x + 1, y: store.y),
                                     Position(x: store.x, y: store.y - 1),
                                     Position(x: store.x, y: store.y + 1)] {
                        guard let route = nav.route(from: tile, to: entrance),
                              route.count <= 512 else { continue }
                        deliveryLength = min(deliveryLength ?? Int.max, route.count)
                    }
                }
                guard let deliveryLength else { continue }
                let cost = pickupRoute.count + deliveryLength
                // Higher initial AI resource priority wins, then shortest
                // total trip; stable ties follow sorted IDs and row-major tiles.
                let priority = collectPriority(at: tile)
                if best == nil || priority > best!.priority ||
                   (priority == best!.priority && cost < best!.cost) {
                    best = (priority, cost, raider.identifier,
                            CollectOrder(tile: tile, route: pickupRoute))
                }
            }
        }
        guard let best else { return nil }
        return IdleCollectAssignment(raiderID: best.raiderID, order: best.order)
    }

    /// Consume exactly ONE item after confirmed arrival at its source tile.
    /// The retail source MAP bytes are unchanged, and this does not increment
    /// NERPs delivered/stored counters.
    @discardableResult
    func collect(_ order: CollectOrder, raiderID: String, raiderAt: Position) -> ResourceUnit? {
        guard !raiderID.isEmpty, carrying[raiderID] == nil,
              raiderAt == order.tile,
              availableCollectUnits(at: order.tile, for: raiderID) > 0,
              NativeLevelNavigation(world: world, excavated: excavated,
                                    revealed: revealed).canWalk(raiderAt),
              let drop = resourceDrops[order.tile], drop.count > 0 else { return nil }
        let item = ResourceUnit(kind: drop.kind, level: drop.level)
        justCollectedOriginalIDs.removeValue(forKey: raiderID)
        if var originals = placedResources[order.tile], !originals.isEmpty {
            // Only consume the head of the physical OL source queue. Stacked
            // same-tile items can have different original types; after the
            // final crystal, the next ore becomes available without mutation
            // of either source file or miscrediting the NERPs kind counter.
            let source = originals.removeFirst()
            guard source.unit == item else { return nil }
            justCollectedOriginalIDs[raiderID] = source.identifier
            if originals.isEmpty {
                placedResources.removeValue(forKey: order.tile)
                resourceDrops[order.tile] = pendingMapDrops.removeValue(forKey: order.tile)
            } else {
                placedResources[order.tile] = originals
                resourceDrops[order.tile] = nextPlacedDeposit(at: order.tile)
            }
        } else if drop.count == 1 {
            resourceDrops.removeValue(forKey: order.tile)
            mapDropSpawnCounts.removeValue(forKey: order.tile)
        }
        else {
            resourceDrops[order.tile] = .init(kind: drop.kind, level: drop.level,
                                              count: drop.count - 1)
        }
        carrying[raiderID] = item
        releaseCollectReservation(raiderID: raiderID)
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

    /// A blocked or interrupted Deposit path must not strand a physical
    /// resource forever. Reappoint an idle *carrying* Raider only when a
    /// genuine original Toolstation is reachable. No stored counter changes
    /// during planning; explicit player orders and active tasks take priority.
    /// This is a bounded retry, not the complete original AITask scheduler.
    struct IdleDepositAssignment {
        let raiderID: String
        let order: DepositOrder
    }

    func planIdleDeposit(raiders: [IdleRaider], busyRaiderIDs: Set<String>,
                         blockedBuildings: Set<Position> = []) -> IdleDepositAssignment? {
        var best: IdleDepositAssignment?
        let idle = raiders.sorted { $0.identifier < $1.identifier }
        for raider in idle {
            guard !raider.identifier.isEmpty,
                  !busyRaiderIDs.contains(raider.identifier),
                  carrying[raider.identifier] != nil,
                  let route = planDeposit(from: raider.tile, raiderID: raider.identifier,
                                          blockedBuildings: blockedBuildings) else { continue }
            // Stable ties favor the original Raider identifier. A previously
            // unreachable store can become available on a later dispatch scan.
            if best == nil || route.route.count < best!.order.route.count {
                best = IdleDepositAssignment(raiderID: raider.identifier, order: route)
            }
        }
        return best
    }

    /// An unrelated building or a remote order never credits inventory.
    /// This mission-local stored counter is exposed to the original NERPs
    /// callback. Building_Deposit and resource processing remain incomplete.
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

    /// Original AITask initialises Clearing at priority 20, below its
    /// Crystal (55) and Ore/DefaultCollect (49) priorities. The caller
    /// schedules this only after available Collect/Deposit work. Choose one
    /// reachable rubble pile for a genuinely idle, non-carrying Raider;
    /// active and in-transit Clear destinations are excluded by the caller.
    /// This is mission-local task assignment, not the complete retail AI.
    struct IdleClearAssignment {
        let raiderID: String
        let order: ClearOrder
    }

    func planIdleClear(raiders: [IdleRaider], busyRaiderIDs: Set<String>,
                       blockedBuildings: Set<Position> = [],
                       excludedTargets: Set<Position> = []) -> IdleClearAssignment? {
        guard !rubbleLayers.isEmpty else { return nil }
        let nav = NativeLevelNavigation(world: world, excavated: excavated,
            revealed: revealed, blockedBuildingTiles: blockedBuildings)
        let targets = rubbleLayers.keys.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }
        let idle = raiders.sorted { $0.identifier < $1.identifier }
        var best: IdleClearAssignment?
        for raider in idle {
            guard !raider.identifier.isEmpty,
                  !busyRaiderIDs.contains(raider.identifier),
                  carrying[raider.identifier] == nil,
                  collectReservations[raider.identifier] == nil,
                  nav.canWalk(raider.tile) else { continue }
            for tile in targets {
                guard !excludedTargets.contains(tile), canClearRubble(tile),
                      let route = nav.route(from: raider.tile, to: tile),
                      route.count <= 512 else { continue }
                if best == nil || route.count < best!.order.route.count {
                    best = IdleClearAssignment(
                        raiderID: raider.identifier, order: ClearOrder(tile: tile, route: route))
                }
            }
        }
        return best
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
            mapDropSpawnCounts[order.wall] = deposit.count
            if hasPlacedResource(at: order.wall) {
                // Keep the already existing OL items ahead of newly released
                // map resources; never overwrite physical objects.
                pendingMapDrops[order.wall] = deposit
            } else {
                resourceDrops[order.wall] = deposit
            }
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
