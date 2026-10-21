import Foundation

/// Original LEGO Rock Raiders level Object List (.ol) file.
///
/// Retail object lists are *text* configuration documents with Lego* /
/// ObjectN sections, not proprietary executable or mesh blobs. See:
/// https://kb.rockraidersunited.com/Object_List_file
///
/// This loader is intentionally read-only and preserves the original spawn
/// coordinates (tile-space floating-point values) and headings. Visual 3D
/// proxies in the native preview are NOT original character models.
struct OriginalObjectList {
    enum ObjectError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self {
            case .invalid(let reason): return "Invalid original OL file: \(reason)"
            }
        }
    }

    struct Placement {
        let identifier: String
        let type: String
        let x: Double
        let y: Double
        let headingDegrees: Double
        let health: Double?
        let drivingIdentifier: String?

        var isCamera: Bool { type.caseInsensitiveCompare("TVCamera") == .orderedSame }
        var isRockRaider: Bool { type.caseInsensitiveCompare("Pilot") == .orderedSame }
    }

    static let maximumObjects = 200
    let placements: [Placement]
    var initialCamera: Placement? { placements.first(where: \.isCamera) }
    var rockRaiders: [Placement] { placements.filter(\.isRockRaider) }

    init(data: Data) throws {
        guard data.count <= 2_000_000 else {
            throw ObjectError.invalid("OL text file exceeds 2MB")
        }
        let cfg = try LegoConfig(data: data)
        let names = cfg.childSections(under: ["Lego*"])
        guard !names.isEmpty else {
            throw ObjectError.invalid("missing original Lego* object sections")
        }
        guard names.count <= Self.maximumObjects else {
            throw ObjectError.invalid("more than 200 placements")
        }

        var result: [Placement] = []
        for name in names {
            let path = ["Lego*", name]
            func required(_ key: String) throws -> String {
                guard let value = cfg.value(path: path + [key]), !value.isEmpty else {
                    throw ObjectError.invalid("\(name) missing \(key)")
                }
                return value
            }
            func numeric(_ key: String) throws -> Double {
                let text = try required(key)
                guard let value = Double(text), value.isFinite,
                      abs(value) <= 1_000_000 else {
                    throw ObjectError.invalid("\(name) has invalid \(key)")
                }
                return value
            }

            let type = try required("type")
            guard type.utf8.count <= 120 else {
                throw ObjectError.invalid("\(name) has oversized type")
            }
            let x = try numeric("xPos")
            let y = try numeric("yPos")
            let heading = try numeric("heading")
            var health: Double?
            if cfg.value(path: path + ["health"]) != nil {
                health = try numeric("health")
            }
            let driving = cfg.value(path: path + ["driving"])
            if let driving, driving.utf8.count > 128 {
                throw ObjectError.invalid("\(name) has oversized driving reference")
            }
            result.append(Placement(identifier: name, type: type, x: x, y: y,
                                    headingDegrees: heading, health: health,
                                    drivingIdentifier: driving))
        }
        placements = result
    }

    init(manifest: LevelRuntimeResources, resources: GameResources) throws {
        guard let file = manifest.objectListPath else {
            // Levels can legitimately omit starting placed objects.
            self.placements = []
            return
        }
        let bytes = try resources.data(at: file, maximumBytes: 2_000_000)
        try self.init(data: bytes)
    }
}
