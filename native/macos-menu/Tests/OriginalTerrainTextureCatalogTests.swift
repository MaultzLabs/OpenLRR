import Foundation

// Synthetic WWAD data only; no game artwork is included in these tests.
private func u32(_ n: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
     UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
}

private func testArchive(_ names: [String]) -> Data {
    var data: [UInt8] = [87, 87, 65, 68] + u32(UInt32(names.count))
    for name in names { data += Array(name.utf8) + [0] }
    for name in names { data += Array(("C:\\Original\\" + name).utf8) + [0] }
    var offset = data.count + names.count * 16
    for _ in names {
        data += u32(1) + u32(2) + u32(2) + u32(UInt32(offset))
        offset += 2
    }
    for _ in names { data += [66, 77] }
    return Data(data)
}

@main struct OriginalTerrainTextureCatalogTests {
    static func main() throws {
        let resources = try GameResources(archives: [(0, testArchive([
            "World\\WorldTextures\\RockSplit\\Rock00.BMP",
            "World\\WorldTextures\\RockSplit\\Rock40.BMP",
            "World\\WorldTextures\\IceSplit\\Ice00.BMP"
        ]))])

        let explicit = OriginalTerrainTextureCatalog(
            textureSetSetting: "World\\WorldTextures\\IceSplit\\Ice:0:0",
            resources: resources)
        precondition(explicit?.family == .ice)
        precondition(explicit?.path(for: 0, resources: resources)?
            .lowercased().hasSuffix("ice00.bmp") == true)

        let rock = OriginalTerrainTextureCatalog(
            textureSetSetting: "World\\WorldTextures\\RockSplit\\Rock:0:0",
            resources: resources)
        precondition(rock?.family == .rock)
        precondition(rock?.bytes(for: 0x40, resources: resources) == Data([66, 77]))
        precondition(rock?.path(for: 0x45, resources: resources) == nil)

        // Do not silently substitute Rock when a configured set is missing.
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: "World\\WorldTextures\\LavaSplit\\Lava:0:0",
            resources: resources) == nil)
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: "CustomRock:0:0",
            resources: resources) == nil)
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: "Rock:bad:0",
            resources: resources) == nil)
        precondition(OriginalTerrainTextureCatalog(
            textureSetSetting: nil, resources: resources)?.family == .rock)
        print("PASS: retail TextureSet prefixes, explicit biome selection, no wrong-biome fallback")
    }
}
