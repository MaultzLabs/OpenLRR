import Foundation

/// Read-only assets for existing OL placements, not building construction or
/// resource spawning. Game.cpp:841–873 and GameCommon.h:184–206 define the
/// special resource names; buildings come from BuildingTypes, not a fixed path.
struct OriginalMissionObjectAsset {
    struct CrystalColor {
        let red: Double
        let green: Double
        let blue: Double

        init(config: LegoConfig) throws {
            guard let value = config.valueUnderGame(["Main", "PowerCrystalRGB"]) else {
                throw OriginalModelActivities.AssetError.invalid("missing Main::PowerCrystalRGB")
            }
            let fields = value.split(separator: ":", omittingEmptySubsequences: false)
            let rgb = fields.compactMap { Double($0) }
            guard fields.count == 3, rgb.count == 3, rgb.allSatisfy({ $0.isFinite && (0...255).contains($0) }) else {
                throw OriginalModelActivities.AssetError.invalid("invalid Main::PowerCrystalRGB \(value)")
            }
            red = rgb[0] / 255; green = rgb[1] / 255; blue = rgb[2] / 255
        }
    }

    enum Contents {
        case building(OriginalLightWaveClipAsset)
        case resource(OriginalLightWaveMeshAsset, CrystalColor?)
    }
    let contents: Contents
    let scale: Double

    static func load(type: String, config: LegoConfig, resources: GameResources) throws -> Self {
        if let directory = config.valueUnderGame(["BuildingTypes", type]) {
            let activities = try OriginalModelActivities.load(directory: directory, resources: resources,
                sharedObjects: config.valueUnderGame(["Main", "SharedObjects"]))
            // Building Stand does not require the Raider-only Route activity.
            return Self(contents: .building(try OriginalLightWaveClipAsset.load(
                activities: activities, activity: "Activity_Stand", resources: resources)), scale: activities.scale)
        }
        let key: String
        switch type.lowercased() {
        case "powercrystal": key = "Crystal"
        case "ore": key = "Ore"
        case "processedore": key = "ProcessedOre"
        default: throw OriginalModelActivities.AssetError.invalid("unsupported OL type \(type)")
        }
        guard let configured = config.valueUnderGame(["MiscObjects", key]) else {
            throw OriginalModelActivities.AssetError.invalid("missing MiscObjects::\(key) for OL \(type)")
        }
        let base = configured.replacingOccurrences(of: "\\", with: "/")
        guard OriginalModelActivities.safe(base) else {
            throw OriginalModelActivities.AssetError.invalid("unsafe MiscObjects::\(key) path \(configured)")
        }
        guard !base.lowercased().hasSuffix(".x") else {
            throw OriginalModelActivities.AssetError.invalid("DirectX .x model unsupported: \(base)")
        }
        // Container_Load(LWO) accepts a configured basename. Also tolerate an
        // explicit .lwo suffix, without searching unrelated resources.
        let path = base + (base.lowercased().hasSuffix(".lwo") ? "" : ".lwo")
        let mesh: OriginalLightWaveMeshAsset
        do { mesh = try OriginalLightWaveMeshAsset.load(path: path, resources: resources) }
        catch {
            let fallback = String(path.dropLast(4)) + ".x"
            if resources.exists(fallback) {
                throw OriginalModelActivities.AssetError.invalid(
                    "\(path) could not load (\(error)); original fallback \(fallback) uses unsupported DirectX .x")
            }
            throw error
        }
        let color = key == "Crystal" ? try CrystalColor(config: config) : nil
        return Self(contents: .resource(mesh, color), scale: 1)
    }
}

/// Shared initial/reveal/diagnostics visibility rule. Real meshes do not depend
/// on the debug-marker switch; unrevealed OL placements remain hidden.
enum OriginalObjectVisibility {
    static func isHidden(discovered: Bool, isRockRaider: Bool, hasOriginalModel: Bool,
                         showObjectMarkers: Bool, isFirstPersonBody: Bool = false) -> Bool {
        !discovered || isFirstPersonBody || (!isRockRaider && !hasOriginalModel && !showObjectMarkers)
    }
}

#if os(macOS)
import AppKit
import SceneKit

/// Placement anchors stay at ground level. Camera/proxy offsets are view
/// presentation details and must not enter original model roots or animations.
enum OriginalObjectPresentation {
    static let diagnosticCenterHeight: CGFloat = 0.48

    static func eyePosition(above ground: SCNVector3) -> SCNVector3 {
        // Same absolute eye height as the old capsule-center + 0.20 camera.
        SCNVector3(ground.x, ground.y + 0.68, ground.z)
    }

    static func placementIdentifier(containing descendant: SCNNode,
                                    anchors: [String: SCNNode]) -> String? {
        var node: SCNNode? = descendant
        while let current = node {
            if let id = anchors.first(where: { $0.value === current })?.key { return id }
            node = current.parent
        }
        return nil
    }
}

final class OriginalMissionObjectModel {
    let root = SCNNode()
    private let clip: OriginalLightWaveRenderer.Clip?
    private let epoch = ProcessInfo.processInfo.systemUptime

    init(asset: OriginalMissionObjectAsset, resources: GameResources, blockSize: Double,
         sharedTextures: String?) throws {
        guard blockSize.isFinite, blockSize > 0 else {
            throw OriginalModelActivities.AssetError.invalid("BlockSize")
        }
        switch asset.contents {
        case .building(let source):
            let loaded = OriginalLightWaveRenderer.Clip(asset: source, resources: resources,
                                                        sharedTextures: sharedTextures)
            clip = loaded
            root.addChildNode(loaded.root)
        case .resource(let source, let crystal):
            clip = nil
            let geometry = OriginalLightWaveRenderer.geometry(asset: source, resources: resources,
                                                               sharedTextures: sharedTextures)
            if let crystal {
                // Object.cpp:1065–1067,1182–1199 initializes powered crystals
                // with Main::PowerCrystalRGB on both diffuse and emissive groups.
                let color = NSColor(calibratedRed: crystal.red, green: crystal.green,
                                    blue: crystal.blue, alpha: 1)
                for material in geometry.materials {
                    material.diffuse.contents = color
                    material.emission.contents = color
                }
            }
            root.addChildNode(SCNNode(geometry: geometry))
        }
        let scale = Float(asset.scale / blockSize)
        root.scale = SCNVector3(scale, scale, scale)
        // Ground origin is the original mesh/scene origin, never a debug sphere
        // or bounding-box recentering. OL placement belongs to the parent node.
    }

    func update(time: TimeInterval) { clip?.update(elapsed: max(0, time - epoch)) }
}
#endif
