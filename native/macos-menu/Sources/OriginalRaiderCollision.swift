import Foundation

/// Stats_Initialise reads the original level-zero Pilot CollRadius in game
/// world units. When that value is zero, the original engine reads CollBox
/// width,height and uses half the larger dimension (Stats.cpp). Convert to
/// native MAP tile coordinates with the configured game BlockSize.
struct OriginalRaiderCollision {
    static let provisionalFallback = 0.23

    static func tileRadius(config: LegoConfig?, blockSize: Double) -> Double {
        guard let config, blockSize.isFinite, blockSize > 0 else {
            return provisionalFallback
        }

        let rawRadius = config.valueUnderGame(["Stats", "Pilot", "CollRadius"])
            .flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let gameUnits: Double?
        if let rawRadius, rawRadius != 0 {
            gameUnits = rawRadius
        } else if let box = config.valueUnderGame(["Stats", "Pilot", "CollBox"]) {
            let parts = box.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2,
               let width = Double(parts[0].trimmingCharacters(in: .whitespacesAndNewlines)),
               let height = Double(parts[1].trimmingCharacters(in: .whitespacesAndNewlines)),
               width.isFinite, height.isFinite, width > 0, height > 0 {
                gameUnits = max(width, height) * 0.5
            } else {
                gameUnits = nil
            }
        } else {
            gameUnits = nil
        }

        guard let gameUnits, gameUnits.isFinite, gameUnits > 0 else {
            return provisionalFallback
        }
        let tiles = gameUnits / blockSize
        // The current tile-clearance sweep is intentionally limited to
        // footprints smaller than half a tile. Never silently clamp the
        // original size and claim authentic collision when unsupported.
        guard tiles.isFinite, tiles > 0, tiles < 0.5 else {
            return provisionalFallback
        }
        return tiles
    }
}
