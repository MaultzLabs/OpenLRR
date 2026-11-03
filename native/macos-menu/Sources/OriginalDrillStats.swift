import Foundation

/// Retail Stats_Initialise reads Lego*::Stats::Pilot drill time in seconds,
/// multiplies by STANDARD_FRAMERATE, and passes that tick count to
/// Level_Block_Damage. The native prototype's SCNAction timer is in seconds,
/// so use the unscaled *level-zero* CFG value. Upgrades and partial damage
/// persistence remain unimplemented.
struct OriginalDrillStats {
    let config: LegoConfig

    func seconds(forTerrainCode code: UInt16) -> Double? {
        // GameCommon.h::Lego_SurfaceType and Game.cpp::Lego_LoadTerrainMap:
        // raw Soil (5) becomes Loose (4) before the retail game drills it.
        let key: String
        switch code {
        case 3: key = "MedDrillTime"
        case 4, 5: key = "LooseDrillTime"
        case 8, 10: key = "SeamDrillTime"
        default: return nil // Hard (2) is not hand-drillable in this prototype.
        }
        guard let raw = config.valueUnderGame(["Stats", "Pilot", key]),
              let levelZero = raw.split(separator: ":", omittingEmptySubsequences: false).first,
              let duration = Double(levelZero.trimmingCharacters(in: .whitespacesAndNewlines)),
              duration.isFinite, duration > 0 else { return nil }
        return duration
    }

    /// Stats_Initialise defaults to these actual preloaded SFX IDs when the
    /// custom Pilot names are missing or cannot be resolved.
    func soundIdentifier(fade: Bool) -> String {
        let key = fade ? "DrillFadeSound" : "DrillSound"
        let fallback = fade ? "SFX_DrillFade" : "SFX_Drill"
        guard let raw = config.valueUnderGame(["Stats", "Pilot", key])?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw.utf8.count <= 256,
              !raw.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return fallback }
        return raw
    }
}
