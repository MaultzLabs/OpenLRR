import Foundation

/// Original building foundation cells, not a substitute collision mesh.
/// Building.cpp::Building_Load prepends (0,0) to up to nine AE Shape offsets.
/// SelectPlace.cpp::SelectPlace_TransformShapePoints rotates the cells, while
/// paired repeated cells denote passable paths or water entrances.
enum NativeBuildingFootprints {
    struct Tile: Hashable {
        let x: Int
        let y: Int
    }

    enum ShapeError: Error {
        case invalidShape
    }

    static func occupiedTiles(shape: String?, origin: Tile, headingDegrees: Double) throws -> Set<Tile> {
        guard headingDegrees.isFinite, abs(headingDegrees) <= 360_000,
              abs(origin.x) <= 1_000_000, abs(origin.y) <= 1_000_000 else {
            throw ShapeError.invalidShape
        }
        var points = [Tile(x: 0, y: 0)]
        if let shape {
            let entries = shape.split(separator: ":", omittingEmptySubsequences: false)
            guard !entries.isEmpty, entries.count <= 9 else { throw ShapeError.invalidShape }
            for entry in entries {
                let values = entry.split(separator: ",", omittingEmptySubsequences: false)
                guard values.count == 2,
                      let x = Int(values[0].trimmingCharacters(in: .whitespaces)),
                      let y = Int(values[1].trimmingCharacters(in: .whitespaces)),
                      abs(x) <= 32, abs(y) <= 32 else {
                    throw ShapeError.invalidShape
                }
                points.append(Tile(x: x, y: y))
            }
        }
        // Object.cpp::HiddenObject_ExposeBlock's eight pie slices use C++
        // truncating signed integer division, not ordinary floating rounding.
        let slice = Int(headingDegrees / 45)
        let orientation = (((slice + 1) / 2) % 4 + 4) % 4
        func transformed(_ point: Tile) -> Tile {
            let x: Int, y: Int
            switch orientation {
            case 1: (x, y) = (-point.y, point.x)
            case 2: (x, y) = (-point.x, -point.y)
            case 3: (x, y) = (point.y, -point.x)
            default: (x, y) = (point.x, point.y)
            }
            return Tile(x: origin.x + x, y: origin.y + y)
        }
        var solid = Set<Tile>()
        var i = 0
        while i < points.count {
            if i + 1 < points.count && points[i] == points[i + 1] {
                // SelectPlace_CheckAndUpdate advances over both repeated
                // entries: these are not solid building foundation tiles.
                i += 2
                continue
            }
            solid.insert(transformed(points[i]))
            i += 1
        }
        return solid
    }
}
