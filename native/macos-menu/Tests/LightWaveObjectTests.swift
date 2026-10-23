import Foundation

@main struct LightWaveObjectTests {
    static func main() throws {
        func be16(_ value: UInt16) -> [UInt8] {
            [UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        func be32(_ value: UInt32) -> [UInt8] {
            [UInt8(truncatingIfNeeded: value >> 24),
             UInt8(truncatingIfNeeded: value >> 16),
             UInt8(truncatingIfNeeded: value >> 8),
             UInt8(truncatingIfNeeded: value)]
        }
        func point(_ x: Float, _ y: Float, _ z: Float) -> [UInt8] {
            be32(x.bitPattern) + be32(y.bitPattern) + be32(z.bitPattern)
        }
        func chunk(_ type: String, _ payload: [UInt8]) -> [UInt8] {
            var result = Array(type.utf8) + be32(UInt32(payload.count)) + payload
            if payload.count % 2 == 1 { result.append(0) }
            return result
        }
        func lwob(_ chunks: [[UInt8]]) -> Data {
            let body = Array("LWOB".utf8) + chunks.flatMap { $0 }
            return Data(Array("FORM".utf8) + be32(UInt32(body.count)) + body)
        }
        let points = point(0, 0, 0) + point(1, 0, 0) +
                     point(1, 0, 1) + point(0, 0, 1)
        let names = Array("Ground".utf8) + [0, 0] +
                    Array("Details".utf8) + [0]
        let quad = be16(4) + be16(0) + be16(1) +
                   be16(2) + be16(3) + be16(1)
        let model = lwob([chunk("PNTS", points),
                          chunk("SRFS", names),
                          chunk("POLS", quad)])
        let mesh = try LightWaveObject(data: model)
        precondition(mesh.vertices.count == 4)
        precondition(mesh.triangles.count == 2)
        precondition(mesh.surfaceNames == ["Ground", "Details"])
        precondition(mesh.triangles[0].first == 0)
        precondition(mesh.triangles[0].second == 1)
        precondition(mesh.triangles[0].third == 2)
        precondition(mesh.triangles[0].surfaceIndex == 0)
        precondition(mesh.triangles[1].third == 3)
        precondition(mesh.vertices[2].z == 1)

        let colorPayload = Array("Ground".utf8) + [0, 0] + Array("COLR".utf8) + be16(4) + [255, 180, 0, 0]
        let colored = try LightWaveObject(data: lwob([
            chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad), chunk("SURF", colorPayload)
        ]))
        precondition(colored.surfaceColors["Ground"]?.red == 255)
        precondition(colored.surfaceColors["Ground"]?.green == 180)
        precondition(colored.surfaceColors["Ground"]?.blue == 0)

        func mustReject(_ name: String, _ data: Data) {
            do {
                _ = try LightWaveObject(data: data)
                preconditionFailure("Invalid LWOB accepted: \(name)")
            } catch is LightWaveObject.MeshError {
                // Correct rejection.
            } catch {
                preconditionFailure("Unexpected LWOB error: \(error)")
            }
        }
        mustReject("truncated surface color", lwob([
            chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad),
            chunk("SURF", Array("Ground".utf8) + [0, 0] + Array("COLR".utf8) + be16(4) + [255, 0])
        ]))
        mustReject("missing header", Data([0, 1, 2, 3]))
        mustReject("bad FORM size", Data(model.dropLast()))
        mustReject("no POLS", lwob([chunk("PNTS", points)]))
        mustReject("invalid vertex index", lwob([
            chunk("PNTS", points),
            chunk("SRFS", names),
            chunk("POLS", be16(3) + be16(0) + be16(1) + be16(99) + be16(1))
        ]))
        mustReject("zero surface ID", lwob([
            chunk("PNTS", points),
            chunk("SRFS", names),
            chunk("POLS", be16(3) + be16(0) + be16(1) + be16(2) + be16(0))
        ]))
        mustReject("bad point length", lwob([
            chunk("PNTS", Array(repeating: 0, count: 13)),
            chunk("SRFS", names), chunk("POLS", quad)
        ]))
        mustReject("NaN model position", lwob([
            chunk("PNTS", be32(Float.nan.bitPattern) + be32(0) + be32(0) +
                         point(0, 0, 0) + point(1, 0, 0) + point(0, 1, 0)),
            chunk("SRFS", names), chunk("POLS", quad)
        ]))
        let detail = be16(3) + be16(0) + be16(1) + be16(2) +
                     be16(UInt16(bitPattern: -1)) + be16(1) +
                     be16(3) + be16(0) + be16(2) + be16(3) + be16(2)
        let withDetail = try LightWaveObject(data: lwob([
            chunk("PNTS", points), chunk("SRFS", names),
            chunk("POLS", detail)
        ]))
        precondition(withDetail.triangles.count == 2)
        precondition(withDetail.triangles[1].surfaceIndex == 1)

        print("PASS: bounded original LWOB vertices, surfaces, polygons, detail faces and malformed data")
    }
}
