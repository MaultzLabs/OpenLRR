#if os(macOS)
import AppKit
import ImageIO
import SceneKit

/// The authentic retail main-menu rock transition: LWSC1 motion plus the
/// actual LWO Boulder meshes / NewRock BMP from the user's own original WAD.
/// See Front_RockWipe_Play and Front_Menu_Update in FrontEnd.cpp.
/// No substitute boulders or copyrighted meshes are bundled in this project.
final class NativeRockWipeView: SCNView {
    private struct AnimatedObject {
        let sceneObject: LightWaveScene.Object
        let node: SCNNode
    }

    private let originalScene: LightWaveScene
    private var animated: [AnimatedObject] = []
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var didSwitch = false
    private var midpointAction: (() -> Void)?
    private var completionAction: (() -> Void)?

    var availableRockModels: Int { animated.filter { $0.node.geometry != nil }.count }

    override var isOpaque: Bool { false }

    static func configuredScenePath(config: LegoConfig,
                                    resources: GameResources) -> String? {
        let value = config.valueUnderGame(["Menu", "MenuWipe"]) ??
                    config.valueUnderGame(["Menu", "!MenuWipe"])
        guard let value, !value.lowercased().hasPrefix("null"),
              value.utf8.count <= 1024 else { return nil }
        let base = value.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\\", with: "/")
        guard !base.contains(".."), !base.contains(":"),
              !base.hasPrefix("/") else { return nil }
        let path = base.lowercased().hasSuffix(".lws") ? base : base + ".lws"
        return resources.exists(path) ? path : nil
    }

    init?(frame: CGRect, config: LegoConfig, resources: GameResources) {
        guard let path = Self.configuredScenePath(config: config,
                                                 resources: resources),
              let data = try? resources.data(at: path, maximumBytes: 4_000_000),
              let script = try? LightWaveScene(data: data) else { return nil }
        originalScene = script
        super.init(frame: frame, options: nil)

        allowsCameraControl = false
        rendersContinuously = false
        backgroundColor = .clear
        wantsLayer = true
        layer?.isOpaque = false

        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 1_000
        camera.position = SCNVector3(0, 0, 5)
        camera.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(camera)
        pointOfView = camera
        let light = SCNNode()
        light.light = SCNLight()
        light.light?.type = .directional
        light.light?.color = NSColor(white: 0.85, alpha: 1)
        light.eulerAngles = SCNVector3(-0.5, 0.65, 0.3)
        scene.rootNode.addChildNode(light)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.color = NSColor(white: 0.25, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        let sceneFolder = path.replacingOccurrences(of: "\\", with: "/")
                              .split(separator: "/").dropLast().joined(separator: "/")
        let textureNames = ["NewRock.bmp", "NewRock2.bmp"]
        var textures: [NSImage] = []
        for name in textureNames {
            let filename = sceneFolder + "/" + name
            guard resources.exists(filename),
                  let bytes = try? resources.data(at: filename, maximumBytes: 4_000_000),
                  let source = CGImageSourceCreateWithData(bytes as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { continue }
            textures.append(NSImage(cgImage: image,
                                    size: CGSize(width: image.width, height: image.height)))
        }

        var nodes: [SCNNode] = []
        for (index, object) in script.objects.enumerated() {
            let node = SCNNode()
            node.name = object.filename ?? "Original LW Null \(index)"
            if let filename = object.filename {
                let paths = LightWaveScene.candidatePaths(reference: filename,
                                                          scenePath: path)
                for candidate in paths {
                    guard resources.exists(candidate),
                          let bytes = try? resources.data(at: candidate,
                                                          maximumBytes: 20_000_000),
                          let mesh = try? LightWaveObject(data: bytes)
                    else { continue }
                    let points = mesh.vertices.map { SCNVector3($0.x, $0.y, $0.z) }
                    let indexes = mesh.triangles.flatMap { triangle -> [UInt32] in
                        [UInt32(triangle.first), UInt32(triangle.second),
                         UInt32(triangle.third)]
                    }
                    let geometry = SCNGeometry(
                        sources: [SCNGeometrySource(vertices: points)],
                        elements: [SCNGeometryElement(indices: indexes,
                                                      primitiveType: .triangles)])
                    let material = SCNMaterial()
                    material.isDoubleSided = true
                    material.lightingModel = .blinn
                    material.diffuse.contents = textures.first ??
                        NSColor(calibratedRed: 0.39, green: 0.32,
                                blue: 0.27, alpha: 1)
                    geometry.materials = [material]
                    node.geometry = geometry
                    break
                }
            }
            nodes.append(node)
            animated.append(AnimatedObject(sceneObject: object, node: node))
        }

        // Classic LWS ParentObject is an index into object declarations. We
        // attach after construction so forward references don't lose geometry.
        for (index, object) in script.objects.enumerated() {
            let parentIndex = object.parentIndex ?? 0
            if parentIndex > 0, parentIndex <= nodes.count,
               parentIndex - 1 != index {
                nodes[parentIndex - 1].addChildNode(nodes[index])
            } else {
                scene.rootNode.addChildNode(nodes[index])
            }
        }
        self.scene = scene
        apply(frame: Double(script.firstFrame))
        // If the original mesh or scene isn't readable yet, caller falls
        // back to direct navigation. Never draw fabricated replacement rocks.
        if availableRockModels == 0 { return nil }
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    private func apply(frame: Double) {
        for part in animated {
            let channels = part.sceneObject.channels(at: frame)
            guard channels.count == 9 else { continue }
            let n = part.node
            n.position = SCNVector3(Float(channels[0]),
                                    Float(channels[1]), Float(channels[2]))
            let degrees = Float.pi / 180
            n.eulerAngles = SCNVector3(Float(channels[4]) * degrees,
                                       Float(channels[3]) * degrees,
                                       Float(channels[5]) * degrees)
            n.scale = SCNVector3(Float(channels[6]),
                                 Float(channels[7]), Float(channels[8]))
        }
    }

    func play(midpoint: @escaping () -> Void, completed: @escaping () -> Void) {
        timer?.invalidate()
        midpointAction = midpoint
        completionAction = completed
        didSwitch = false
        startedAt = ProcessInfo.processInfo.systemUptime
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0,
                                      repeats: true) { [weak self] _ in
            self?.advance()
        }
    }

    private func advance() {
        // Original Front_Menu_Update drives RockWipe at 2 original frames
        // per standard 25Hz unit = 50 animation frames per second.
        let elapsed = max(0, ProcessInfo.processInfo.systemUptime - startedAt)
        let frame = min(Double(originalScene.lastFrame),
                        Double(originalScene.firstFrame) + elapsed * 50)
        apply(frame: frame)
        if !didSwitch &&
           frame >= Double(originalScene.firstFrame +
                            originalScene.lastFrame) / 2 {
            didSwitch = true
            midpointAction?()
        }
        if frame >= Double(originalScene.lastFrame) {
            timer?.invalidate()
            timer = nil
            if !didSwitch { midpointAction?() }
            completionAction?()
            midpointAction = nil
            completionAction = nil
        }
    }
}
#endif
