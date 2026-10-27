import Foundation

@main struct NativeBuildingFootprintsTests {
    static func main() throws {
        typealias F = NativeBuildingFootprints
        func tile(_ x: Int, _ y: Int) -> F.Tile { .init(x: x, y: y) }
        let origin = tile(6, 5)
        func expect(_ shape: String?, _ degrees: Double, _ result: Set<F.Tile>) throws {
            let actual = try F.occupiedTiles(shape: shape, origin: origin, headingDegrees: degrees)
            precondition(actual == result, "Unexpected occupied tiles for \(shape ?? "default") at \(degrees)")
        }
        try expect(nil, 0, [origin])
        let square: Set<F.Tile> = [tile(6,5), tile(7,5), tile(7,6), tile(6,6)]
        try expect("1,0:1,1:0,1", 0, square)
        try expect("1,0", 90, [origin, tile(6,6)])
        try expect("1,0", 180, [origin, tile(5,5)])
        try expect("1,0", 270, [origin, tile(6,4)])
        try expect("1,0", -90, [origin, tile(7,5)]) // Original C++ signed division.
        try expect("1,0", 44, [origin, tile(7,5)])
        try expect("1,0", 46, [origin, tile(6,6)])
        // Adjacent identical offsets encode a passable path/entrance.
        try expect("1,0:1,0:0,1", 0, [origin, tile(6,6)])
        try expect("0,0", 0, [])
        for shape in ["", "1", "1,", "1,2,3", "1,2:", "1,a", "33,0",
                      "1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0:1,0"] {
            do {
                _ = try F.occupiedTiles(shape: shape, origin: origin, headingDegrees: 0)
                preconditionFailure("Malformed Shape accepted: \(shape)")
            } catch F.ShapeError.invalidShape {}
        }
        do {
            _ = try F.occupiedTiles(shape: nil, origin: origin, headingDegrees: .nan)
            preconditionFailure("Non-finite heading accepted")
        } catch F.ShapeError.invalidShape {}
        print("PASS: original AE building Shape, rotations, entrances and malformed inputs")
    }
}
