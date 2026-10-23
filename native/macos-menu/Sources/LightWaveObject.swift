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

    let vertices: [Vertex]
    let triangles: [Triangle]
    struct Color { let red: UInt8; let green: UInt8; let blue: UInt8 }
    let surfaceColors: [String: Color]
    let surfaceNames: [String]

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
        var colorChunks: [Range<Int>] = []
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
            case "SURF": colorChunks.append(chunkStart..<chunkEnd)
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
        for chunk in colorChunks {
            guard let endName = data[chunk].firstIndex(of: 0) else {
                throw MeshError.invalid("unterminated SURF name")
            }
            let name = String(decoding: data[chunk.lowerBound..<endName], as: UTF8.self)
            let nameLength = endName - chunk.lowerBound + 1
            var offset = endName + 1 + (nameLength & 1)
            while offset + 6 <= chunk.upperBound {
                let tag = String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
                let length = Int(be16(offset + 4))
                offset += 6
                guard length <= chunk.upperBound - offset else {
                    throw MeshError.invalid("truncated SURF subchunk")
                }
                if tag == "COLR" {
                    guard length >= 3 else { throw MeshError.invalid("short COLR") }
                    colors[name] = Color(red: data[offset], green: data[offset + 1], blue: data[offset + 2])
                }
                offset += length + (length & 1)
            }
            guard offset == chunk.upperBound else { throw MeshError.invalid("SURF alignment") }
        }
        surfaceColors = colors
        vertices = decodedVertices
        triangles = decodedTriangles
        surfaceNames = decodedSurfaces
    }
}
