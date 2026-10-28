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

        let uvText = """
        2
        2
        Ground
        Details
        face.bmp
        uniform.bmp
        1
        0 4
        0 0
        1 0
        1 1
        0 1
        """
        let uv = try LightWaveUVMap(data: Data(uvText.utf8), mesh: mesh)
        precondition(uv.images == ["face.bmp", "uniform.bmp"])
        precondition(uv.corners.count == 1 && uv.corners[0].count == 4)
        precondition(uv.corners[0][2].u == 1 && uv.corners[0][2].v == -1)
        for bad in [uvText.replacingOccurrences(of: "0 4", with: "1 4"),
                    uvText.replacingOccurrences(of: "0 4", with: "0 3"),
                    uvText.replacingOccurrences(of: "1 1", with: "nan 1"),
                    String(uvText.dropLast(4))] {
            do { _ = try LightWaveUVMap(data: Data(bad.utf8), mesh: mesh)
                preconditionFailure("Invalid UV sidecar accepted")
            } catch is LightWaveObject.MeshError { }
        }
        func subchunk(_ tag: String, _ bytes: [UInt8]) -> [UInt8] {
            Array(tag.utf8) + be16(UInt16(bytes.count)) + bytes + (bytes.count % 2 == 1 ? [0] : [])
        }
        let texturePayload = Array("Ground".utf8) + [0, 0] +
            subchunk("TIMG", Array("Face.bmp".utf8) + [0]) +
            subchunk("TFLG", be16(1)) + subchunk("TSIZ", point(2, 4, 8)) + subchunk("TCTR", point(1, 2, 3))
        let textured = try LightWaveObject(data: lwob([chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad), chunk("SURF", texturePayload)]))
        let texture = textured.surfaceTextures["Ground"]!
        precondition(texture.image == "Face.bmp")
        let projected = texture.uv(.init(x: 3, y: 6, z: 11))
        precondition(projected.u == 1.5 && projected.v == 1.5)

        func surfaceModel(_ fields: [UInt8], name: String = "Ground") throws -> LightWaveObject {
            let string = Array(name.utf8) + [0]
            let payload = string + (string.count % 2 == 1 ? [0] : []) + fields
            return try LightWaveObject(data: lwob([chunk("PNTS", points), chunk("SRFS", names),
                chunk("POLS", quad), chunk("SURF", payload)]))
        }
        var materialFields = subchunk("COLR", [128, 64, 255, 0])
        for (tag, value) in [("FLAG", 0x188), ("DIFF", 128), ("LUMI", 64),
                              ("TRAN", 192), ("SPEC", 32), ("GLOS", 512)] {
            materialFields += subchunk(tag, be16(UInt16(value)))
        }
        let withMaterial = try surfaceModel(materialFields, name: "gRoUnD")
        let material = withMaterial.material(named: "GROUND")
        precondition(material.isDoubleSided && !material.isAdditive)
        precondition(material.flags == 0x188 && material.opacity == 0.25)
        precondition(material.diffuse == 0.5 && material.luminosity == 0.25)
        precondition(material.specular == 0.125 && material.glossiness == 2,
                     "SPEC/GLOS are uint16 / 256, not floats or unscaled GLOS")
        precondition(material.baseColor(textured: false).red == 0.5)
        precondition(material.baseColor(textured: false).blue == 255 / 256.0)
        precondition(material.diffuseColor(textured: false).red == 0.25)
        precondition(material.emissionColor(textured: false).green == 0.0625)
        precondition(material.baseColor(textured: true).green == 0.25,
                     "SHARPTERMINATOR retains COLR with a texture")

        let withoutSharp = try surfaceModel(subchunk("COLR", [128, 64, 255, 0]) +
            subchunk("FLAG", be16(0x201)) + subchunk("DIFF", be16(256)))
        let additive = withoutSharp.material(named: "Ground")
        precondition(additive.isAdditive && !additive.isDoubleSided)
        precondition(additive.baseColor(textured: true).red == 1)
        precondition(additive.baseColor(textured: true).green == 1)
        precondition(additive.baseColor(textured: false).green == 0.25)
        precondition(additive.luminosity == 0,
                     "The LUMINOUS flag does not replace the source LUMI scalar")

        // The parser must not invent defaults for omitted material chunks.
        let blank = try surfaceModel([]).material(named: "Ground")
        precondition(blank.flags == 0 && blank.diffuse == 0 && blank.luminosity == 0)
        precondition(blank.specular == 0 && blank.glossiness == 0 && blank.opacity == 1)
        precondition(blank.color.red == 0 && !blank.isDoubleSided)
        let unmatched = mesh.material(named: "Missing")
        precondition(unmatched.color.red == 255 && unmatched.diffuse == 0 && unmatched.opacity == 1)

        // Fixed-point values can exceed unity; retain their bytes and apply
        // Mesh_SetGroupColour/Alpha's clamp at the final untextured channels.
        let bright = try surfaceModel(subchunk("COLR", [64, 128, 255, 0]) +
            subchunk("DIFF", be16(512)) + subchunk("LUMI", be16(65535)) +
            subchunk("TRAN", be16(512))).material(named: "Ground")
        precondition(bright.diffuseColor(textured: false).red == 0.5)
        precondition(bright.diffuseColor(textured: false).green == 1)
        precondition(bright.diffuseColor(textured: false).blue == 1)
        precondition(bright.emissionColor(textured: false).red == 1)
        precondition(bright.luminosity == 65535 / 256.0 && bright.opacity == 0)

        // TTEX owns a separate LWSURFACE in the original loader. Even COLR,
        // FLAG and scalar material fields after it cannot leak into layer zero.
        var nestedFields = materialFields
        nestedFields += subchunk("TIMG", Array("Base.bmp".utf8) + [0])
        nestedFields += subchunk("TFLG", be16(0x20))
        nestedFields += subchunk("TTEX", Array("Planar Image Map".utf8) + [0])
        nestedFields += subchunk("COLR", [1, 2, 3, 0])
        for tag in ["FLAG", "DIFF", "LUMI", "TRAN", "SPEC", "GLOS"] {
            nestedFields += subchunk(tag, be16(0))
        }
        nestedFields += subchunk("TIMG", Array("Other.bmp".utf8) + [0])
        let layered = try surfaceModel(nestedFields)
        let base = layered.material(named: "Ground")
        precondition(base.color.red == 128 && base.flags == 0x188 && base.diffuse == 0.5)
        precondition(base.luminosity == 0.25 && base.opacity == 0.25)
        precondition(base.specular == 0.125 && base.glossiness == 2)
        precondition(base.texture.image == "Base.bmp" && base.texture.flags == 0x20)
        precondition(layered.surfaceColors["Ground"]?.red == 128)
        let lowerTag = try surfaceModel(subchunk("diff", be16(256)))
        precondition(lowerTag.material(named: "Ground").diffuse == 1)
        let duplicate = try LightWaveObject(data: lwob([
            chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad),
            chunk("SURF", Array("Ground".utf8) + [0, 0] + materialFields),
            chunk("SURF", Array("GROUND".utf8) + [0, 0] + subchunk("DIFF", be16(256)))
        ]))
        precondition(duplicate.material(named: "Ground").diffuse == 0.5,
                     "LoadLWOB selects the first case-insensitive matching surface")

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
        for tag in ["FLAG", "DIFF", "LUMI", "TRAN", "SPEC", "GLOS"] {
            for length in [0, 1, 3, 4] {
                for prefix in [[], subchunk("TTEX", [0, 0])] {
                    mustReject("invalid \(tag) length \(length)", lwob([
                        chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad),
                        chunk("SURF", Array("Ground".utf8) + [0, 0] + prefix +
                            subchunk(tag, Array(repeating: 0, count: length)))
                    ]))
                }
            }
        }
        for length in [0, 1, 2, 3, 5] {
            mustReject("invalid COLR length \(length)", lwob([
                chunk("PNTS", points), chunk("SRFS", names), chunk("POLS", quad),
                chunk("SURF", Array("Ground".utf8) + [0, 0] + subchunk("COLR", Array(repeating: 0, count: length)))
            ]))
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

        let seamUV = try LightWaveUVMap(data: Data("""
        2
        2
        Ground
        Details
        face.bmp
        uniform.bmp
        2
        0 3
        0 0
        1 0
        1 1
        1 3
        0.5 0.5
        1 1
        0 1
        """.utf8), mesh: withDetail)
        // Both polygons use original vertex 0, but their UV corners differ.
        precondition(seamUV.corners[0][0].u == 0)
        precondition(seamUV.corners[1][0].u == 0.5)

        print("PASS: bounded original LWOB vertices, surfaces, polygons, detail faces and malformed data")
    }
}
