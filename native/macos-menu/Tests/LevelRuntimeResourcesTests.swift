import Foundation

private func word(_ v: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
     UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
}
private func syntheticWad(_ files: [(String, [UInt8])]) -> Data {
    var bytes = [UInt8]([87, 87, 65, 68]) + word(UInt32(files.count))
    for (name, _) in files { bytes += Array(name.utf8) + [0] }
    for (name, _) in files { bytes += Array(("C:\\Original\\" + name).utf8) + [0] }
    var offset = bytes.count + files.count * 16
    for (_, payload) in files {
        bytes += word(1) + word(UInt32(payload.count)) +
                 word(UInt32(payload.count)) + word(UInt32(offset))
        offset += payload.count
    }
    for (_, payload) in files { bytes += payload }
    return Data(bytes)
}
private func syntheticMap(_ values: [UInt16], width: UInt32, height: UInt32) -> [UInt8] {
    var bytes: [UInt8] = [77, 65, 80, 32]
    bytes += word(8 + UInt32(values.count * 2))
    bytes += word(width)
    bytes += word(height)
    for value in values {
        bytes += [UInt8(truncatingIfNeeded: value),
                  UInt8(truncatingIfNeeded: value >> 8)]
    }
    return bytes
}

@main struct LevelRuntimeResourcesTests {
    static func main() throws {
        let cfg = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              FullName Driller_Night
              TerrainMap Levels\\GameLevels\\Level01\\Surf.map
              PredugMap Levels\\GameLevels\\Level01\\Dugg.map
              SurfaceMap Levels\\GameLevels\\Level01\\High.map
              OListFile Levels\\GameLevels\\Level01\\Objects.ol
              NERPFile Levels\\GameLevels\\Level01\\Level01.npl
              NextLevel Levels::Level02
            }
          }
        }
        """)
        let manifest = try LevelRuntimeResources(config: cfg, identifier: "Levels::Level01")
        precondition(manifest.title == "Driller Night")
        precondition(manifest.mapPaths.count == 3)
        precondition(manifest.objectListPath?.hasSuffix("Objects.ol") == true)
        precondition(manifest.scriptPath?.hasSuffix("Level01.npl") == true)
        precondition(manifest.nextLevel == "Levels::Level02")

        let first = syntheticMap([0, 4, 9, 5], width: 2, height: 2)
        let exposed = syntheticMap([0, 1, 2, 1], width: 2, height: 2)
        let height = syntheticMap([1, 1, 2, 2], width: 2, height: 2)
        let wad = syntheticWad([
            ("Levels\\GameLevels\\Level01\\Surf.map", first),
            ("Levels\\GameLevels\\Level01\\Dugg.map", exposed),
            ("Levels\\GameLevels\\Level01\\High.map", height)
        ])
        let archive = try GameResources(archives: [(0, wad)])
        let maps = try manifest.loadMaps(resources: archive)
        precondition(maps.count == 3)
        precondition(maps["TerrainMap"]?.value(x: 1, y: 0) == 4)
        precondition(maps["PredugMap"]?.value(x: 0, y: 1) == 2)
        precondition(maps["SurfaceMap"]?.value(x: 1, y: 1) == 2)

        do {
            _ = try LevelRuntimeResources(config: cfg, identifier: "Main::Other")
            preconditionFailure("non-level identifier was accepted")
        } catch is LevelRuntimeResources.RuntimeError {}
        let unsafe = try LegoConfig(text: """
        Lego* {
          Levels {
            Level01 {
              TerrainMap ..\\secret.map
            }
          }
        }
        """)
        do {
            _ = try LevelRuntimeResources(config: unsafe, identifier: "Levels::Level01")
            preconditionFailure("unsafe original level resource path was accepted")
        } catch is LevelRuntimeResources.RuntimeError {}

        print("PASS: authentic level map paths, native 16-bit decoding, and unsafe path rejection")
    }
}
