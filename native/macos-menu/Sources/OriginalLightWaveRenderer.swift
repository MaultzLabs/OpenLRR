#if os(macOS)
import AppKit
import SceneKit
import ImageIO

/// One rendering path for original Raider, building and resource LWOB models.
/// Keep polygon-corner UVs, surface grouping and the retail LWS pivot matrix
/// here so static mission objects cannot drift from character rendering.
enum OriginalLightWaveRenderer {
    static func geometry(asset: OriginalLightWaveMeshAsset, resources: GameResources,
                         sharedTextures: String?) -> SCNGeometry {
        let mesh = asset.mesh, meshPath = asset.path, uvMap = asset.uvMap
        let vertices = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
        var normals = Array(repeating: SCNVector3Zero, count: mesh.vertices.count)
        for triangle in mesh.triangles {
            let a = vertices[triangle.first], b = vertices[triangle.second], c = vertices[triangle.third]
            let u = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let v = SCNVector3(c.x - a.x, c.y - a.y, c.z - a.z)
            let normal = SCNVector3(u.y * v.z - u.z * v.y, u.z * v.x - u.x * v.z, u.x * v.y - u.y * v.x)
            for i in [triangle.first, triangle.second, triangle.third] {
                normals[i] = SCNVector3(normals[i].x + normal.x, normals[i].y + normal.y, normals[i].z + normal.z)
            }
        }
        normals = normals.map { n in
            let length = sqrt(n.x * n.x + n.y * n.y + n.z * n.z)
            return length > 0 ? SCNVector3(n.x / length, n.y / length, n.z / length) : SCNVector3(0, 1, 0)
        }
        var renderVertices: [SCNVector3] = [], renderNormals: [SCNVector3] = []
        var coordinates: [CGPoint] = []
        var groups: [Int: [UInt32]] = [:]
        for (polygonID, polygon) in mesh.polygons.enumerated() {
            let surfaceName = polygon.surfaceIndex < mesh.surfaceNames.count ? mesh.surfaceNames[polygon.surfaceIndex] : ""
            let projection = mesh.material(named: surfaceName).texture
            let start = renderVertices.count
            for (corner, vertexID) in polygon.indices.enumerated() {
                renderVertices.append(vertices[vertexID])
                renderNormals.append(normals[vertexID])
                let uv = uvMap?.corners[polygonID][corner] ?? projection.uv(mesh.vertices[vertexID])
                // D3D texture V grows down; SceneKit's grows up.
                coordinates.append(CGPoint(x: CGFloat(uv.u), y: CGFloat(1 - uv.v)))
            }
            for corner in 1..<(polygon.indices.count - 1) {
                groups[polygon.surfaceIndex, default: []].append(contentsOf: [UInt32(start), UInt32(start + corner), UInt32(start + corner + 1)])
            }
        }
        var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
        for index in groups.keys.sorted() {
            elements.append(SCNGeometryElement(indices: groups[index]!, primitiveType: .triangles))
            let material = SCNMaterial()
            let name = index < mesh.surfaceNames.count ? mesh.surfaceNames[index] : ""
            let surface = mesh.material(named: name)
            material.isDoubleSided = surface.isDoubleSided
            material.cullMode = .back
            // Mesh_SetMeshRenderDesc explicitly disables specular lighting.
            // Retain SPEC/GLOS in the parser without inventing shiny Phong art.
            material.lightingModel = .lambert
            material.specular.contents = NSColor.black
            // Mesh_CreateGroupMaterial initializes ambient reflectance to zero.
            material.locksAmbientWithDiffuse = false
            material.ambient.contents = NSColor.black
            let reference = uvMap.flatMap { $0.images.indices.contains(index) ? $0.images[index] : nil } ?? surface.texture.image
            let textured = !reference.isEmpty
            material.diffuse.contents = color(surface.diffuseColor(textured: textured))
            material.emission.contents = color(surface.emissionColor(textured: textured))
            material.transparency = CGFloat(surface.opacity)
            material.transparencyMode = .aOne
            // Standard source-alpha opacity is an approximation of D3D's
            // ordered alpha pass. Additive/color-key modes remain unported.
            material.blendMode = .alpha
            material.writesToDepthBuffer = surface.opacity == 1 && !surface.isAdditive
            // Mesh.cpp:598–658,1724–1758 strips the texture's
            // author path, then tries mesh-local before SharedTextures.
            let candidates = LightWaveResourcePaths.candidates(reference: reference,
                assetPath: meshPath, sharedDirectory: sharedTextures, requiredExtension: "bmp")
            if let imagePath = candidates.first(where: { resources.exists($0) }),
               let bytes = try? resources.data(at: imagePath, maximumBytes: 4_000_000),
               let source = CGImageSourceCreateWithData(bytes as CFData, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                let contents = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                material.diffuse.contents = contents
                material.emission.contents = contents
                material.diffuse.intensity = CGFloat(surface.diffuse)
                material.emission.intensity = CGFloat(surface.luminosity)
                material.multiply.contents = color(surface.baseColor(textured: true))
                // SceneKit's separate material channels approximate D3D's
                // texture × (lit diffuse + emissive). Saturation above unity,
                // lighting, blending order and color space are not identical.
                let pixelBlending = surface.texture.flags & 0x20 != 0
                for channel in [material.diffuse, material.emission] {
                    channel.wrapS = .repeat
                    channel.wrapT = .repeat
                    channel.magnificationFilter = pixelBlending ? .linear : .nearest
                    channel.minificationFilter = pixelBlending ? .linear : .nearest
                    channel.mipFilter = .none
                }
            }
            materials.append(material)
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: renderVertices), SCNGeometrySource(normals: renderNormals), SCNGeometrySource(textureCoordinates: coordinates)], elements: elements)
        geometry.materials = materials
        return geometry
    }

    private static func color(_ rgb: LightWaveObject.Surface.RGB) -> NSColor {
        NSColor(calibratedRed: CGFloat(rgb.red), green: CGFloat(rgb.green),
                blue: CGFloat(rgb.blue), alpha: 1)
    }

    final class Clip {
        let asset: OriginalLightWaveClipAsset
        let root = SCNNode()
        let parts: [SCNNode]

        init(asset: OriginalLightWaveClipAsset, resources: GameResources, sharedTextures: String?) {
            self.asset = asset
            parts = zip(asset.scene.objects, asset.components).map { object, mesh in
                let node = SCNNode()
                node.name = object.filename
                if let mesh {
                    node.geometry = OriginalLightWaveRenderer.geometry(asset: mesh, resources: resources,
                                                                      sharedTextures: sharedTextures)
                }
                return node
            }
            for (index, object) in asset.scene.objects.enumerated() {
                if let parent = object.parentIndex, parent > 0 {
                    parts[parent - 1].addChildNode(parts[index])
                } else { root.addChildNode(parts[index]) }
            }
            update(elapsed: 0)
        }

        func update(elapsed: TimeInterval) {
            let frame = asset.frame(elapsed: elapsed)
            for (object, node) in zip(asset.scene.objects, parts) {
                let channels = object.channels(at: frame)
                // Exact bank/pitch/heading matrix from Lws_SetupNodeTransform.
                let r = Double.pi / 180
                let cx = cos(channels[4] * r), sx = sin(channels[4] * r)
                let cy = cos(channels[3] * r), sy = sin(channels[3] * r)
                let cz = cos(channels[5] * r), sz = sin(channels[5] * r)
                var m = SCNMatrix4Identity
                m.m11 = CGFloat((cz * cy + sz * sx * sy) * channels[6])
                m.m12 = CGFloat(sz * cx * channels[6])
                m.m13 = CGFloat((sz * sx * cy - cz * sy) * channels[6])
                m.m21 = CGFloat((cz * sx * sy - sz * cy) * channels[7])
                m.m22 = CGFloat(cz * cx * channels[7])
                m.m23 = CGFloat((sz * sy + cz * sx * cy) * channels[7])
                m.m31 = CGFloat(cx * sy * channels[8])
                m.m32 = CGFloat(-sx * channels[8])
                m.m33 = CGFloat(cx * cy * channels[8])
                let px = CGFloat(-object.pivot[0]), py = CGFloat(-object.pivot[1]), pz = CGFloat(-object.pivot[2])
                m.m41 = m.m11 * px + m.m21 * py + m.m31 * pz + CGFloat(channels[0])
                m.m42 = m.m12 * px + m.m22 * py + m.m32 * pz + CGFloat(channels[1])
                m.m43 = m.m13 * px + m.m23 * py + m.m33 * pz + CGFloat(channels[2])
                node.transform = m
            }
        }
    }
}
#endif
