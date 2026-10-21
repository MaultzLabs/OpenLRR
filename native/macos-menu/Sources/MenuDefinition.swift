import Foundation

/// Read-only model of the real FrontEnd definitions from Lego.cfg.
/// Supports config-defined navigation and end triggers, never fake gameplay.
struct MenuDefinition {
    struct Item {
        enum Kind: Equatable { case next, trigger, cycle, slider, select, unknown(String) }
        let kind: Kind
        let x: Int
        let y: Int
        let caption: String
        let imageNormal: String?
        let imageHover: String?
        let linkedMenu: Int?
        let endsMenu: Bool
        let raw: String
    }

    struct Overlay {
        let asset: String
        let x: Int
        let y: Int
    }

    struct Screen {
        let title: String
        let internalName: String
        let x: Int
        let y: Int
        let autoCenter: Bool
        let canScroll: Bool
        let displayTitle: Bool
        let titleAnchorY: Int
        let backgroundImage: String?
        let darkBackgroundImage: String?
        let titleFont: String?
        let normalFont: String?
        let hoverFont: String?
        let overlays: [Overlay]
        let items: [Item]
    }

    let menus: [Screen]

    /// OpenLRR passes triggerQuitApp to the second MainMenuFull trigger.
    /// In the retail configuration that is the terminal "ARE YOU SURE?"
    /// Yes item. Prefer matching the actual confirmation screen title.
    var quitConfirmationIndex: Int? {
        let candidates = menus.indices.filter { index in
            menus[index].items.contains(where: { $0.kind == .trigger && $0.endsMenu })
        }
        return candidates.first(where: { index in
            let name = (menus[index].title + " " + menus[index].internalName)
                .lowercased().replacingOccurrences(of: "_", with: " ")
            return name.contains("are you sure") || name.contains("quit?")
        }) ?? candidates.first(where: { $0 > 0 })
    }

    enum MenuError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self { case .invalid(let message): return "Invalid front-end menu: \(message)" }
        }
    }

    init(config: LegoConfig, menuSetName: String = "MainMenuFull") throws {
        let set = ["Menu", menuSetName]
        func value(_ path: [String]) -> String? { config.valueUnderGame(path) }
        guard let number = value(set + ["MenuCount"]),
              let count = Int(number), (1...64).contains(count) else {
            throw MenuError.invalid("missing or unsupported \(menuSetName) MenuCount")
        }
        var result: [Screen] = []
        result.reserveCapacity(count)
        for index in 1...count {
            let path = set + ["Menu\(index)"]
            let location = (value(path + ["Position"]) ?? "0:0").split(separator: ":")
            func intPart(_ string: Substring?) -> Int { string.flatMap { Int($0) } ?? 0 }
            let px = intPart(location.first)
            let py = intPart(location.dropFirst().first)
            let title = (value(path + ["Title"]) ?? "").replacingOccurrences(of: "_", with: " ")
            // Front_LoadMenuSet reads FullName and only draws it when DisplayTitle
            // is enabled. Never synthesize an absent original menu label.
            let fullName = (value(path + ["FullName"]) ?? "").replacingOccurrences(of: "_", with: " ")
            // Front_LoadMenuSet reads AutoCenter for banner text positions.
            let autoCenter = ["TRUE", "YES", "ON", "1"].contains(
                (value(path + ["AutoCenter"]) ?? "FALSE").uppercased())
            let canScroll = ["TRUE", "YES", "ON", "1"].contains(
                (value(path + ["CanScroll"]) ?? "FALSE").uppercased())
            let displayTitle = !["NO", "FALSE", "OFF"].contains(
                (value(path + ["DisplayTitle"]) ?? "TRUE").uppercased())
            let anchorParts = (value(path + ["Anchored"]) ?? "")
                .split(separator: ":", omittingEmptySubsequences: false)
            let titleAnchorY = anchorParts.count == 2 ? (Int(anchorParts[1]) ?? 0) : 0
            let declaredItems = Int(value(path + ["ItemCount"]) ?? "0") ?? 0
            guard (0...150).contains(declaredItems) else {
                throw MenuError.invalid("unreasonable ItemCount in \(menuSetName)/Menu\(index)")
            }
            var overlays: [Overlay] = []
            for overlayNumber in 1...32 {
                guard let raw = value(path + ["Overlay\(overlayNumber)"]) ??
                                value(path + ["!Overlay\(overlayNumber)"]) else { break }
                let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
                guard parts.count == 4 else { continue }
                overlays.append(Overlay(asset: String(parts[0]),
                                        x: Int(parts[2]) ?? 0,
                                        y: Int(parts[3]) ?? 0))
            }
            var items: [Item] = []
            // An original menu may legitimately contain zero items.
            // 1...0 traps in optimized Swift; 1..<1 is an empty range.
            for itemNumber in 1..<(declaredItems + 1) {
                guard let raw = value(path + ["Item\(itemNumber)"]) else { continue }
                let fields = raw.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
                guard fields.count >= 3 else { continue }
                let type = fields[0].lowercased()
                let x = Int(fields[1]) ?? 0, y = Int(fields[2]) ?? 0
                let kind: Item.Kind
                switch type {
                case "next": kind = .next
                case "trigger": kind = .trigger
                case "cycle": kind = .cycle
                case "slider", "realslider": kind = .slider
                case "select": kind = .select
                default: kind = .unknown(fields[0])
                }
                // OpenLRR Front_LoadMenuSet: 8-field Next/Trigger = image item.
                // 5-field Next/Trigger = original banner item.
                let imageMode = fields.count == 8 && (kind == .next || kind == .trigger)
                let normal = imageMode ? fields[3] : nil
                let hovered = imageMode ? fields[4] : nil
                let banner = imageMode ? "" : (fields.count >= 4 ? fields[3] : "")
                let caption = banner.replacingOccurrences(of: "_", with: " ")
                var linked: Int?
                if kind == .next {
                    let linkIndex = imageMode ? 7 : 4
                    if fields.indices.contains(linkIndex) {
                        let link = fields[linkIndex]
                        if link.lowercased().hasPrefix("menu"),
                           let number = Int(link.dropFirst(4)),
                           (1...count).contains(number) {
                            linked = number - 1
                        }
                    }
                }
                // Front_LoadMenuSet: Trigger has 5 or 8 fields, final field
                // is numeric `end`. Only end==1 may close a menu.
                let end = kind == .trigger &&
                          (fields.count == 5 || fields.count == 8) &&
                          fields.last == "1"
                items.append(Item(kind: kind, x: x, y: y, caption: caption,
                                  imageNormal: normal?.isEmpty == true ? nil : normal,
                                  imageHover: hovered?.isEmpty == true ? nil : hovered,
                                  linkedMenu: linked, endsMenu: end, raw: raw))
            }
            result.append(Screen(title: title, internalName: fullName,
                                 x: px, y: py, autoCenter: autoCenter, canScroll: canScroll,
                                 displayTitle: displayTitle,
                                 titleAnchorY: titleAnchorY,
                                 backgroundImage: value(path + ["MenuImage"]),
                                 darkBackgroundImage: value(path + ["MenuImageDark"]),
                                 titleFont: value(path + ["MenuFont"]),
                                 normalFont: value(path + ["LoFont"]),
                                 hoverFont: value(path + ["HiFont"]),
                                 overlays: overlays,
                                 items: items))
        }
        self.menus = result
    }
}
