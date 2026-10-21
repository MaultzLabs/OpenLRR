import Foundation

/// Resolves the retail Pointer_Standard BMP from Lego.cfg, as registered by
/// src/openlrr/game/interface/Pointers.cpp. Cursor art stays in the user's WAD.
/// Pointer_Load passes a single Windows BMP filename for Standard/Blank.
struct OriginalPointerAsset {
    static func standardPath(config: LegoConfig, resources: GameResources) -> String? {
        let names = [
            ["Pointers", "Pointer_Standard"],
            ["Pointers", "Standard"],
            ["Pointers", "!Pointer_Standard"],
            ["Pointers", "!Standard"]
        ]
        for path in names {
            guard let raw = config.valueUnderGame(path) else { continue }
            let candidate = raw.split(separator: ",", maxSplits: 1)
                .first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard isSafeBMP(candidate), resources.exists(candidate) else { continue }
            return candidate
        }

        // Some localized/modified CFGs omit the Standard entry. These are
        // known original Retail BMP filenames, never external artwork.
        for path in ["Interface/Pointers/PointerOpen.bmp",
                     "Interface/Pointers/PointerBack.bmp"] {
            if resources.exists(path) { return path }
        }
        return nil
    }

    private static func isSafeBMP(_ path: String) -> Bool {
        guard path.utf8.count < 512,
              path.lowercased().hasSuffix(".bmp") else { return false }
        let parts = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        return !parts.isEmpty && parts.allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains(":")
        }
    }
}
