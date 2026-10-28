import Foundation

// Entirely synthetic archive paths/payloads, including author-machine decoys.
private struct FixtureAsset {
    let path: String
    let bytes: Data
    var flags: UInt32 = 1
}

private func fixtureWad(_ assets: [FixtureAsset]) -> Data {
    func u32(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }
    var bytes = Array("WWAD".utf8) + u32(UInt32(assets.count))
    for asset in assets { bytes += Array(asset.path.utf8) + [0] }
    for asset in assets { bytes += Array(("Z:\\Fixture\\" + asset.path).utf8) + [0] }
    var offset = bytes.count + assets.count * 16
    for asset in assets {
        bytes += u32(asset.flags) + u32(UInt32(asset.bytes.count)) +
            u32(UInt32(asset.bytes.count)) + u32(UInt32(offset))
        offset += asset.bytes.count
    }
    for asset in assets { bytes.append(contentsOf: asset.bytes) }
    return Data(bytes)
}

@main struct OriginalRaiderModelTests {
    static func main() throws {
        let definition = try LegoConfig(text: """
        Lego* {
          CameraNullName Camera
          CameraNullFrames 2
          Activities {
            Activity_Stand Stand
            Activity_Route Walk
          }
          Stand {
            FILE PilotStand
            LWSFILE TRUE
          }
          Walk {
            FILE PilotWalk.lws
            LWSFILE TRUE
          }
        }
        """)
        let activities = try OriginalRaiderActivities(directory: "MiniFigures\\Pilot", definition: definition)
        precondition(activities.cameraNullPartName(frame: 0) == "Camera_00")
        precondition(activities.cameraNullPartName(frame: 1) == "Camera_01")
        precondition(activities.cameraNullPartName(frame: 2) == nil)
        precondition(activities.cameraNullPartName(frame: -1) == nil)
        let stand = try activities.scenePath(activity: "Activity_Stand")
        precondition(stand == "MiniFigures/Pilot/PilotStand.lws")
        let walk = try activities.scenePath(activity: "Activity_Route")
        precondition(walk == "MiniFigures/Pilot/PilotWalk.lws")
        do {
            _ = try activities.scenePath(activity: "Activity_Drill")
            preconditionFailure("Missing animation must not become a fabricated clip")
        } catch OriginalRaiderActivities.AssetError.invalid { }
        for path in ["../Pilot", "/Pilot", "C:/Pilot", "Pilot//Parts"] {
            do {
                _ = try OriginalRaiderActivities(directory: path, definition: definition)
                preconditionFailure("Unsafe model path")
            } catch OriginalRaiderActivities.AssetError.invalid { }
        }
        try testConfiguredSharedObjects()
        testOrderedCandidates()
        try testArchiveResolution()
        print("PASS: original AE activities, ordered scene/mesh-local and configured shared lookup, archive overrides and safe basename-only paths")
    }

    static func testConfiguredSharedObjects() throws {
        let config = try LegoConfig(text: """
        Lego* {
          MiniFigureTypes {
            Pilot Fixture\\Pilot
          }
          Main {
            SharedObjects Fixture\\SharedObjects\\
          }
        }
        """)
        let definition = Data("""
        Lego* {
          Activities {
            Activity_Stand Stand
          }
          Stand {
            FILE Stand
            LWSFILE TRUE
          }
        }
        """.utf8)
        let resources = try GameResources(archives: [(0, fixtureWad([
            FixtureAsset(path: "Fixture/Pilot/Pilot.ae", bytes: definition)
        ]))])
        let loaded = try OriginalRaiderActivities.load(config: config, resources: resources)
        precondition(loaded.sharedObjects == "Fixture\\SharedObjects\\")
        let scenePath = try loaded.scenePath(activity: "Activity_Stand")
        precondition(LightWaveScene.candidatePaths(reference: "D:\\Author\\Body.lwo",
            scenePath: scenePath, sharedObjects: loaded.sharedObjects) == [
                "Fixture/Pilot/Body.lwo", "Fixture/SharedObjects/Body.lwo"
            ])
    }

    static func testOrderedCandidates() {
        let scene = "ZFixture/Scene/Stand.lws"
        let shared = "AFixture/Shared"
        let expected = ["ZFixture/Scene/Body.lwo", "AFixture/Shared/Body.lwo"]
        // Local wins even when shared or author directories sort before it.
        // Neither absolute nor relative author directories are lookup roots.
        for reference in ["Body.lwo", "AFixture/Author/Body.lwo", "D:\\Author\\Body.lwo",
                          "\\\\server\\Author\\Body.lwo", "/tmp/Author/Body.lwo", "../Author/Body.lwo"] {
            precondition(LightWaveScene.candidatePaths(reference: reference,
                scenePath: scene, sharedObjects: shared) == expected)
        }
        precondition(LightWaveScene.candidatePaths(reference: "Body.lwo",
            scenePath: "ZFixture\\Scene\\Stand.lws", sharedObjects: "AFixture\\Shared\\") == expected)
        precondition(LightWaveScene.candidatePaths(reference: "Body.lwo", scenePath: scene) == [expected[0]])
        precondition(LightWaveScene.candidatePaths(reference: "Body.lwo",
            scenePath: scene, sharedObjects: "zfixture/SCENE/") == [expected[0]])
        precondition(LightWaveScene.candidatePaths(reference: "Body.lwo", scenePath: "Stand.lws") == ["Body.lwo"])
        precondition(LightWaveScene.candidatePaths(reference: "D:\\Author\\Body part.LWO", scenePath: scene) ==
                     ["ZFixture/Scene/Body part.LWO"])

        for reference in ["", ".", "..", "Body.bmp", "Body.lwo/", "C:Body.lwo",
                          "Body\0.lwo", "Author\n/Body.lwo", String(repeating: "x", count: 257) + ".lwo"] {
            precondition(LightWaveScene.candidatePaths(reference: reference,
                scenePath: scene, sharedObjects: shared).isEmpty)
        }
        for unsafe in ["/tmp/Shared", "\\\\host\\Shared", "C:\\Shared", "../Shared",
                       "Shared/../Other", "Shared/./Other", "Shared//Other", "Shared\0", ""] {
            precondition(LightWaveScene.candidatePaths(reference: "Body.lwo",
                scenePath: scene, sharedObjects: unsafe) == [expected[0]])
            precondition(LightWaveScene.candidatePaths(reference: "Body.lwo",
                scenePath: unsafe + "/Stand.lws", sharedObjects: shared).isEmpty)
        }
        // Mesh_LoadTexture has the same basename rule, but uses the mesh's
        // directory (which may itself be SharedObjects), not the scene's.
        precondition(LightWaveResourcePaths.candidates(reference: "D:\\Author\\Face.BMP",
            assetPath: "AFixture/Shared/Body.lwo", sharedDirectory: "Fixture\\Textures\\",
            requiredExtension: "bmp") == ["AFixture/Shared/Face.BMP", "Fixture/Textures/Face.BMP"])
        precondition(LightWaveResourcePaths.candidates(reference: "Face.BMP", assetPath: "Body.lwo",
            sharedDirectory: nil, requiredExtension: "bmp") == ["Face.BMP"])
        precondition(LightWaveResourcePaths.candidates(reference: "Face.png", assetPath: "Body.lwo",
            sharedDirectory: "Fixture/Textures", requiredExtension: "bmp").isEmpty)
    }

    static func testArchiveResolution() throws {
        // Run both component and bitmap lookups through the production helper.
        for (ext, asset) in [("lwo", "Stand.lws"), ("bmp", "Body.lwo")] {
            let local = "ZFixture/Scene/Part.\(ext)", shared = "AFixture/Shared/Part.\(ext)"
            let author = "AFixture/Author/Part.\(ext)"
            let paths = LightWaveResourcePaths.candidates(reference: author,
                assetPath: "ZFixture/Scene/" + asset, sharedDirectory: "AFixture/Shared", requiredExtension: ext)
            precondition(paths == [local, shared])
            let lower = fixtureWad([FixtureAsset(path: local, bytes: Data([0x10]))])
            let decoys = [FixtureAsset(path: author, bytes: Data([0xee])),
                          FixtureAsset(path: "ZFixture/Scene/" + author, bytes: Data([0xef]))]
            let sharedAssets = decoys + [FixtureAsset(path: shared, bytes: Data([0x20]))]
            let resources = try GameResources(archives: [(0, lower), (1, fixtureWad(sharedAssets))])
            let selected = paths.first(where: { resources.exists($0) })
            precondition(selected == local, "Local in WAD0 must beat shared in WAD1")
            let localBytes = try resources.data(at: selected!)
            precondition(localBytes == Data([0x10]))

            let overrides = try GameResources(archives: [(1, fixtureWad(sharedAssets + [
                FixtureAsset(path: local.uppercased(), bytes: Data([0x11]))
            ])), (0, lower)])
            let overridePath = paths.first(where: { overrides.exists($0) })
            precondition(overridePath == local)
            let overrideBytes = try overrides.data(at: overridePath!)
            precondition(overrideBytes == Data([0x11]), "WAD1 must override WAD0 at the selected path")

            let fallback = try GameResources(archives: [(0, fixtureWad([
                FixtureAsset(path: shared, bytes: Data([0x20]))
            ])), (1, fixtureWad(decoys + [FixtureAsset(path: shared.uppercased(), bytes: Data([0x21]))]))])
            let fallbackPath = paths.first(where: { fallback.exists($0) })
            precondition(fallbackPath == shared)
            let fallbackBytes = try fallback.data(at: fallbackPath!)
            precondition(fallbackBytes == Data([0x21]))

            let authorOnly = try GameResources(archives: [(0, fixtureWad(decoys))])
            precondition(paths.first(where: { authorOnly.exists($0) }) == nil,
                         "Author path must not become a third archive fallback")

            let compressed = try GameResources(archives: [(0, lower), (1, fixtureWad(sharedAssets + [
                FixtureAsset(path: local, bytes: Data([0x30]), flags: 3)
            ]))])
            let compressedPath = paths.first(where: { compressed.exists($0) })
            precondition(compressedPath == local)
            do {
                _ = try compressed.data(at: compressedPath!)
                preconditionFailure("Unreadable higher-priority entry must not use lower/shared data")
            } catch WadArchive.WadError.unsupportedCompression { }
        }
    }
}
