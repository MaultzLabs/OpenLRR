import Foundation

/// Read-only decoder for the original game's classic LightWave object models.
/// The retail WAD contains .lwo parts under World/ProMeshes; this handles
/// IFF FORM/LWOB (LightWave 2.x/3.x) point and polygon geometry.
///
/// Source: Allen Hastings/Stuart Ferguson, LightWave 3D Object File Format
/// (1994) https://paulbourke.org/dataformats/lightwave/
/// No proprietary meshes, user WAD bytes, or converted assets are stored here.
/// Animated .lws/.ae scene skeletons and textured surface UVs are separate.
struct LightWaveObject {
    struct Vertex {
        let x: Float
        let y: Float
        let z: Float
    }

    struct Triangle {
        let first: Int
        let second: Int
        let third: Int
        let surfaceIndex: Int
    }

    enum MeshError: Error, CustomStringConvertible {
        case invalid(String)
        var description: String {
            switch self {
            case .invalid(let message): return "Invalid classic LightWave model: \(message)"
            }
        }
    }

    struct Polygon { let indices: [Int]; let surfaceIndex: Int }
    struct Texture {
        var image: String = ""
        var flags: UInt16 = 0
        var size = Vertex(x: 1, y: 1, z: 1)
        var center = Vertex(x: 0, y: 0, z: 0)
        // Mesh_GetTextureUVsWrap, original engine/gfx/Mesh.cpp.
        func uv(_ vertex: Vertex) -> UV {
            let x = vertex.x - center.x, y = vertex.y - center.y, z = vertex.z - center.z
            return UV(u: ((flags & 1) != 0 ? z / size.z : x / size.x) + 0.5,
                      v: ((flags & 2) != 0 ? z / size.z : y / size.y) + 0.5)
        }
    }
    struct UV { let u: Float; let v: Float }
    let polygons: [Polygon]
    let surfaceTextures: [String: Texture]
    let vertices: [Vertex]
    let triangles: [Triangle]
    struct Color { let red: UInt8; let green: UInt8; let blue: UInt8 }
    let surfaceColors: [String: Color]
    let surfaceNames: [String]
    /// Lwt::SURFprc zero-initializes each surface, then reads the original
    /// uint16 fixed-point fields as value / 256 (including SPEC and GLOS).
    /// Do not substitute LightWave-editor defaults for absent chunks.
    struct Surface {
        struct RGB {
            let red: Float
            let green: Float
            let blue: Float
            func scaled(_ amount: Float) -> RGB {
                // Mesh_SetGroupColour clamps after multiplying each channel.
                RGB(red: min(1, max(0, red * amount)),
                    green: min(1, max(0, green * amount)),
                    blue: min(1, max(0, blue * amount)))
            }
        }
        var color = Color(red: 0, green: 0, blue: 0)
        var flags: UInt16 = 0
        var diffuse: Float = 0
        var luminosity: Float = 0
        var transparency: Float = 0
        var specular: Float = 0
        var glossiness: Float = 0
        var texture = Texture()

        var isDoubleSided: Bool { flags & 0x100 != 0 }
        var isAdditive: Bool { flags & 0x200 != 0 }
        var opacity: Float { min(1, max(0, 1 - transparency)) }
        func baseColor(textured: Bool) -> RGB {
            // Mesh_GetSurfInfo uses white for a declared texture unless
            // SFM_SHARPTERMINATOR is set. COLR uses /256, not /255.
            if textured && flags & 0x80 == 0 { return RGB(red: 1, green: 1, blue: 1) }
            return RGB(red: Float(color.red) / 256, green: Float(color.green) / 256,
                       blue: Float(color.blue) / 256)
        }
        func diffuseColor(textured: Bool) -> RGB { baseColor(textured: textured).scaled(diffuse) }
        func emissionColor(textured: Bool) -> RGB { baseColor(textured: textured).scaled(luminosity) }
    }
    /// Canonical names follow LoadLWOB's case-insensitive SRFS/SURF match.
    let surfaceMaterials: [String: Surface]
    func material(named name: String) -> Surface {
        // LoadLWOB's unmatched SRFS placeholder is white, with zero scalars.
        surfaceMaterials[name.lowercased()] ?? Surface(color: Color(red: 255, green: 255, blue: 255))
    }

    init(data: Data) throws {
        guard data.count >= 12, data.count <= 20_000_000,
              String(decoding: data[0..<4], as: UTF8.self) == "FORM",
              String(decoding: data[8..<12], as: UTF8.self) == "LWOB" else {
            throw MeshError.invalid("expected bounded FORM/LWOB model")
        }
        func be16(_ offset: Int) -> UInt16 {
            (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
        }
        func be32(_ offset: Int) -> UInt32 {
            (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
        }
        let formSize = Int(be32(4))
        guard formSize >= 4 && formSize <= data.count - 8 else {
            throw MeshError.invalid("invalid IFF FORM length")
        }
        let end = formSize + 8
        var position = 12
        var pointRange: Range<Int>?
        var polygonRange: Range<Int>?
        var surfaceRange: Range<Int>?
        var surfaceChunks: [Range<Int>] = []
        while position + 8 <= end {
            let fourCC = String(decoding: data[position..<(position + 4)],
                                as: UTF8.self)
            let length = Int(be32(position + 4))
            let chunkStart = position + 8
            guard length <= end - chunkStart else {
                throw MeshError.invalid("truncated IFF \(fourCC) chunk")
            }
            let chunkEnd = chunkStart + length
            switch fourCC {
            case "PNTS": pointRange = chunkStart..<chunkEnd
            case "POLS": polygonRange = chunkStart..<chunkEnd
            case "SRFS": surfaceRange = chunkStart..<chunkEnd
            case "SURF": surfaceChunks.append(chunkStart..<chunkEnd)
            default: break
            }
            position = chunkEnd + (length & 1)
        }
        guard position == end,
              let points = pointRange,
              let polygons = polygonRange,
              points.count % 12 == 0,
              points.count > 0,
              points.count / 12 <= 150_000 else {
            throw MeshError.invalid("missing/oversized points or polygon chunk")
        }

        var decodedVertices: [Vertex] = []
        decodedVertices.reserveCapacity(points.count / 12)
        for offset in stride(from: points.lowerBound, to: points.upperBound, by: 12) {
            let x = Float(bitPattern: be32(offset))
            let y = Float(bitPattern: be32(offset + 4))
            let z = Float(bitPattern: be32(offset + 8))
            guard x.isFinite, y.isFinite, z.isFinite,
                  abs(x) < 1_000_000, abs(y) < 1_000_000, abs(z) < 1_000_000 else {
                throw MeshError.invalid("invalid 3D model coordinates")
            }
            decodedVertices.append(Vertex(x: x, y: y, z: z))
        }

        var decodedSurfaces: [String] = []
        if let surfaces = surfaceRange {
            var cursor = surfaces.lowerBound
            while cursor < surfaces.upperBound {
                guard let terminator = (cursor..<surfaces.upperBound).first(where: {
                    data[$0] == 0
                }) else {
                    throw MeshError.invalid("unterminated SRFS name")
                }
                let nameData = data[cursor..<terminator]
                guard nameData.count <= 256 else {
                    throw MeshError.invalid("oversized surface name")
                }
                decodedSurfaces.append(String(decoding: nameData, as: UTF8.self))
                let consumed = terminator + 1 - cursor
                cursor = terminator + 1 + (consumed & 1)
            }
            guard cursor == surfaces.upperBound else {
                throw MeshError.invalid("bad SRFS name alignment")
            }
        }

        var decodedTriangles: [Triangle] = []
        var decodedPolygons: [Polygon] = []
        var cursor = polygons.lowerBound
        func parsePolygon(detail: Bool) throws -> Int {
            guard cursor + 2 <= polygons.upperBound else {
                throw MeshError.invalid("truncated polygon vertex count")
            }
            let count = Int(be16(cursor))
            cursor += 2
            guard (3...256).contains(count),
                  count <= (polygons.upperBound - cursor - 2) / 2 else {
                throw MeshError.invalid("unsupported polygon or truncated indices")
            }
            var indices: [Int] = []
            indices.reserveCapacity(count)
            for _ in 0..<count {
                let index = Int(be16(cursor))
                cursor += 2
                guard index < decodedVertices.count else {
                    throw MeshError.invalid("polygon index outside PNTS")
                }
                indices.append(index)
            }
            let surfaceRaw = Int(Int16(bitPattern: be16(cursor)))
            cursor += 2
            guard surfaceRaw != 0 && surfaceRaw != Int(Int16.min) else {
                throw MeshError.invalid("invalid polygon surface number")
            }
            let surfaceIndex = abs(surfaceRaw) - 1
            if !decodedSurfaces.isEmpty && surfaceIndex >= decodedSurfaces.count {
                throw MeshError.invalid("polygon surface exceeds SRFS")
            }
            guard decodedTriangles.count <= 400_000 - (count - 2) else {
                throw MeshError.invalid("excessive model triangles")
            }
            decodedPolygons.append(Polygon(indices: indices, surfaceIndex: surfaceIndex))
            for index in 1..<(count - 1) {
                decodedTriangles.append(Triangle(first: indices[0],
                                                  second: indices[index],
                                                  third: indices[index + 1],
                                                  surfaceIndex: surfaceIndex))
            }
            return surfaceRaw
        }

        while cursor < polygons.upperBound {
            let surface = try parsePolygon(detail: false)
            if surface < 0 {
                guard cursor + 2 <= polygons.upperBound else {
                    throw MeshError.invalid("missing detail polygon count")
                }
                let detailCount = Int(be16(cursor))
                cursor += 2
                guard detailCount <= 2048 else {
                    throw MeshError.invalid("excessive detail polygons")
                }
                for _ in 0..<detailCount {
                    let nested = try parsePolygon(detail: true)
                    if nested < 0 {
                        throw MeshError.invalid("nested detail polygons unsupported")
                    }
                }
            }
        }
        guard !decodedTriangles.isEmpty else {
            throw MeshError.invalid("no model triangles")
        }
        var colors: [String: Color] = [:]
        var textures: [String: Texture] = [:]
        var materials: [String: Surface] = [:]
        for chunk in surfaceChunks {
            guard let endName = data[chunk].firstIndex(of: 0) else {
                throw MeshError.invalid("unterminated SURF name")
            }
            let name = String(decoding: data[chunk.lowerBound..<endName], as: UTF8.self)
            guard endName - chunk.lowerBound <= 256 else { throw MeshError.invalid("oversized SURF name") }
            let nameLength = endName - chunk.lowerBound + 1
            var offset = endName + 1 + (nameLength & 1)
            var texture = Texture()
            var material = Surface()
            var additionalLayer = false
            while offset + 6 <= chunk.upperBound {
                let tag = String(decoding: data[offset..<(offset + 4)], as: UTF8.self).uppercased()
                let length = Int(be16(offset + 4))
                offset += 6
                guard length <= chunk.upperBound - offset else {
                    throw MeshError.invalid("truncated SURF subchunk")
                }
                if tag == "TTEX" { additionalLayer = true }
                // TTEX advances Lwt's srfb to a separate linked surface. Its
                // material/color chunks must not overwrite the base surface.
                // Validate known fixed-size fields even in unsupported layers.
                if ["FLAG", "DIFF", "LUMI", "TRAN", "SPEC", "GLOS"].contains(tag), length != 2 {
                    throw MeshError.invalid("invalid \(tag) size")
                }
                if tag == "COLR", length != 4 { throw MeshError.invalid("invalid COLR size") }
                if !additionalLayer {
                    switch tag {
                    case "COLR":
                        material.color = Color(red: data[offset], green: data[offset + 1], blue: data[offset + 2])
                        colors[name] = material.color
                    case "FLAG": material.flags = be16(offset)
                    case "DIFF": material.diffuse = Float(be16(offset)) / 256
                    case "LUMI": material.luminosity = Float(be16(offset)) / 256
                    case "TRAN": material.transparency = Float(be16(offset)) / 256
                    case "SPEC": material.specular = Float(be16(offset)) / 256
                    case "GLOS": material.glossiness = Float(be16(offset)) / 256
                    case "TIMG":
                        guard let zero = data[offset..<(offset + length)].firstIndex(of: 0) else {
                            throw MeshError.invalid("unterminated TIMG")
                        }
                        texture.image = String(decoding: data[offset..<zero], as: UTF8.self)
                    case "TFLG":
                        guard length >= 2 else { throw MeshError.invalid("short TFLG") }
                        texture.flags = be16(offset)
                    case "TSIZ", "TCTR":
                        guard length == 12 else { throw MeshError.invalid("invalid texture vector") }
                        let v = Vertex(x: Float(bitPattern: be32(offset)), y: Float(bitPattern: be32(offset + 4)), z: Float(bitPattern: be32(offset + 8)))
                        guard v.x.isFinite, v.y.isFinite, v.z.isFinite,
                              tag != "TSIZ" || (abs(v.x) > 0.000001 && abs(v.y) > 0.000001 && abs(v.z) > 0.000001) else {
                            throw MeshError.invalid("invalid texture projection")
                        }
                        if tag == "TSIZ" { texture.size = v } else { texture.center = v }
                    default: break
                    }
                }
                offset += length + (length & 1)
            }
            guard offset == chunk.upperBound else { throw MeshError.invalid("SURF alignment") }
            textures[name] = texture
            material.texture = texture
            // LoadLWOB selects the first matching SURF when ordering SRFS.
            if materials[name.lowercased()] == nil { materials[name.lowercased()] = material }
        }
        self.polygons = decodedPolygons
        surfaceTextures = textures
        surfaceColors = colors
        surfaceMaterials = materials
        vertices = decodedVertices
        triangles = decodedTriangles
        surfaceNames = decodedSurfaces
    }
}


/// Original UView version 2 sidecar: surface names, image overrides, and
/// per-polygon corner coordinates. Keep corners separate to preserve UV seams.
struct LightWaveUVMap {
    let images: [String]
    let corners: [[LightWaveObject.UV]]
    init(data: Data, mesh: LightWaveObject) throws {
        guard data.count <= 16_000_000, let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw LightWaveObject.MeshError.invalid("oversized/invalid UV sidecar")
        }
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var cursor = 0
        func line() throws -> String {
            guard cursor < lines.count else { throw LightWaveObject.MeshError.invalid("truncated UV sidecar") }
            defer { cursor += 1 }; return lines[cursor]
        }
        guard try line() == "2", try Int(line()) == mesh.surfaceNames.count else {
            throw LightWaveObject.MeshError.invalid("UV version/surface count")
        }
        for _ in mesh.surfaceNames { _ = try line() }
        var images: [String] = []
        for _ in mesh.surfaceNames { images.append(try line()) }
        guard try Int(line()) == mesh.polygons.count else { throw LightWaveObject.MeshError.invalid("UV polygon count") }
        var corners = Array<[LightWaveObject.UV]?>(repeating: nil, count: mesh.polygons.count)
        for _ in mesh.polygons {
            let header = try line().split(whereSeparator: { $0.isWhitespace })
            guard header.count == 2, let id = Int(header[0]), corners.indices.contains(id), corners[id] == nil,
                  let count = Int(header[1]), count == mesh.polygons[id].indices.count else {
                throw LightWaveObject.MeshError.invalid("UV polygon ID/corner count")
            }
            var values: [LightWaveObject.UV] = []
            for _ in 0..<count {
                let fields = try line().split(whereSeparator: { $0.isWhitespace })
                guard fields.count >= 2, let u = Float(fields[0]), let v = Float(fields[1]),
                      u.isFinite, v.isFinite, abs(u) < 1_000_000, abs(v) < 1_000_000 else {
                    throw LightWaveObject.MeshError.invalid("invalid UV coordinate")
                }
                values.append(.init(u: u, v: -v))
            }
            corners[id] = values
        }
        self.images = images
        self.corners = corners.map { $0! }
    }
}
