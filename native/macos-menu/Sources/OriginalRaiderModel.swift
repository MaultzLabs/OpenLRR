import Foundation

/// Container_Load(ACT) and Creature_Load: <directory>/<basename>.ae,
/// Activities::Activity_Stand/Route -> named section -> FILE + LWSFILE.
struct OriginalRaiderActivities {
    enum AssetError: Error { case invalid(String) }
    let directory: String
    let definition: LegoConfig

    init(directory: String, definition: LegoConfig) throws {
        let normalized = directory.replacingOccurrences(of: "\\", with: "/")
        guard Self.safe(normalized) else { throw AssetError.invalid("model directory") }
        self.directory = normalized
        self.definition = definition
    }

    static func safe(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count <= 1024 && !path.contains(":") &&
        !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    static func load(config: LegoConfig, resources: GameResources) throws -> Self {
        guard let directory = config.valueUnderGame(["MiniFigureTypes", "Pilot"])?
            .replacingOccurrences(of: "\\", with: "/"), Self.safe(directory),
              let name = directory.split(separator: "/").last else {
            throw AssetError.invalid("MiniFigureTypes::Pilot")
        }
        let data = try resources.data(at: "\(directory)/\(name).ae", maximumBytes: 1_000_000)
        return try Self(directory: directory, definition: LegoConfig(data: data))
    }

    func scenePath(activity: String) throws -> String {
        guard let section = definition.valueUnderGame(["Activities", activity]) ??
                definition.valueUnderGame(["Activities", "!" + activity]),
              let file = definition.valueUnderGame([section, "FILE"]),
              let lws = definition.valueUnderGame([section, "LWSFILE"]),
              ["TRUE", "YES", "ON", "1"].contains(lws.uppercased()) else {
            throw AssetError.invalid("missing LWS activity \(activity)")
        }
        let relative = file.replacingOccurrences(of: "\\", with: "/")
        guard Self.safe(relative) else { throw AssetError.invalid("activity file") }
        return directory + "/" + relative + (relative.lowercased().hasSuffix(".lws") ? "" : ".lws")
    }
}

#if os(macOS)
import AppKit
import SceneKit

/// Real LWS hierarchy and LWOB component geometry, no generated character.
/// Surface colors are original COLR values; texture mapping is still pending.
final class OriginalRaiderModel {
    struct Clip {
        let scene: LightWaveScene
        let root: SCNNode
        let parts: [SCNNode]
    }
    let root = SCNNode()
    private let standing: Clip
    private let walking: Clip
    private var moving = false
    private var epoch = ProcessInfo.processInfo.systemUptime

    init(activities: OriginalRaiderActivities, resources: GameResources, blockSize: Double) throws {
        guard blockSize.isFinite, blockSize > 0 else {
            throw OriginalRaiderActivities.AssetError.invalid("BlockSize")
        }
        func clip(_ activity: String) throws -> Clip {
            let path = try activities.scenePath(activity: activity)
            let scene = try LightWaveScene(data: resources.data(at: path, maximumBytes: 4_000_000))
            var parts: [SCNNode] = []
            var meshCount = 0
            for object in scene.objects {
                let node = SCNNode()
                node.name = object.filename
                if let filename = object.filename {
                    guard let meshPath = LightWaveScene.candidatePaths(reference: filename, scenePath: path)
                        .first(where: { resources.exists($0) }) else {
                        throw OriginalRaiderActivities.AssetError.invalid("missing component \(filename)")
                    }
                    let mesh = try LightWaveObject(data: resources.data(at: meshPath, maximumBytes: 20_000_000))
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
                    let groups = Dictionary(grouping: mesh.triangles, by: { $0.surfaceIndex })
                    var elements: [SCNGeometryElement] = [], materials: [SCNMaterial] = []
                    for index in groups.keys.sorted() {
                        let indices = groups[index]!.flatMap { [UInt32($0.first), UInt32($0.second), UInt32($0.third)] }
                        elements.append(SCNGeometryElement(indices: indices, primitiveType: .triangles))
                        let material = SCNMaterial()
                        material.isDoubleSided = true
                        material.lightingModel = .lambert
                        if index < mesh.surfaceNames.count,
                           let color = mesh.surfaceColors[mesh.surfaceNames[index]] {
                            material.diffuse.contents = NSColor(calibratedRed: CGFloat(color.red) / 255,
                                green: CGFloat(color.green) / 255, blue: CGFloat(color.blue) / 255, alpha: 1)
                        } else { material.diffuse.contents = NSColor.gray }
                        materials.append(material)
                    }
                    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: elements)
                    geometry.materials = materials
                    node.geometry = geometry
                    meshCount += 1
                }
                parts.append(node)
            }
            guard meshCount > 0 else { throw OriginalRaiderActivities.AssetError.invalid("empty model") }
            let container = SCNNode()
            for (index, object) in scene.objects.enumerated() {
                if let parent = object.parentIndex, parent > 0 {
                    parts[parent - 1].addChildNode(parts[index])
                } else { container.addChildNode(parts[index]) }
            }
            return Clip(scene: scene, root: container, parts: parts)
        }
        standing = try clip("Activity_Stand")
        walking = try clip("Activity_Route")
        root.addChildNode(standing.root)
        root.addChildNode(walking.root)
        walking.root.isHidden = true
        // Match the native terrain's one-unit-per-original-block coordinates.
        let scale = Float(1 / blockSize)
        root.scale = SCNVector3(scale, scale, scale)
        root.position.y = -0.48 // Parent is located at the proxy capsule's center.
        update(time: epoch)
    }

    func setMoving(_ value: Bool) {
        guard moving != value else { return }
        moving = value
        epoch = ProcessInfo.processInfo.systemUptime
        standing.root.isHidden = moving
        walking.root.isHidden = !moving
    }

    func update(time: TimeInterval) {
        let clip = moving ? walking : standing
        let frame = Double(clip.scene.firstFrame) +
            (max(0, time - epoch) * clip.scene.framesPerSecond)
                .truncatingRemainder(dividingBy: Double(max(1, clip.scene.frameCount)))
        for (object, node) in zip(clip.scene.objects, clip.parts) {
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
#endif
