import Foundation

private func le(_ n: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: n), UInt8(truncatingIfNeeded: n >> 8),
     UInt8(truncatingIfNeeded: n >> 16), UInt8(truncatingIfNeeded: n >> 24)]
}
private func fixture(path: String, payload: [UInt8], flags: UInt32 = 1,
                     lengthOverride: UInt32? = nil, offsetOverride: UInt32? = nil) -> Data {
    let name = Array(path.utf8) + [0]
    let original = Array("C:\\old\\".utf8) + name
    let offset = 8 + name.count + original.count + 16
    var result: [UInt8] = [87, 87, 65, 68]
    result += le(1)
    result += name
    result += original
    result += le(flags)
    result += le(UInt32(payload.count))
    result += le(lengthOverride ?? UInt32(payload.count))
    result += le(offsetOverride ?? UInt32(offset))
    result += payload
    return Data(result)
}
private func expectFailure(_ data: Data, containing phrase: String) {
    do {
        _ = try WadArchive(data: data)
        fatalError("Expected malformed archive to be rejected: \(phrase)")
    } catch {
        precondition(String(describing: error).contains(phrase), "wrong failure: \(error)")
    }
}

@main struct Tests {
    static func main() throws {
        let path = "Interface\\FrontEnd\\MenuBGpic.bmp"
        let bmp = [UInt8]([66,77,1,2,3,4,5])
        let wad = try WadArchive(data: fixture(path: path, payload: bmp))
        precondition(wad.entries.count == 1)
        precondition(wad.contains("interface/frontend/menubgpic.bmp"))
        precondition(wad.contains("INTERFACE\\FRONTEND\\MENUBGPIC.BMP"))
        let loadedBMP = try wad.asset("Interface/FrontEnd/MenuBGpic.bmp")
        precondition(loadedBMP == Data(bmp))
        do {
            _ = try wad.asset("nope")
            fatalError("Missing assets must fail")
        } catch WadArchive.WadError.notFound(_) { }
        expectFailure(Data([0,1,2,3]), containing: "signature")
        var hugeCount = Data([87,87,65,68] + le(UInt32.max) + [0,0])
        expectFailure(hugeCount, containing: "file count")
        hugeCount = fixture(path: path, payload: bmp, offsetOverride: 9999999)
        expectFailure(hugeCount, containing: "outside the archive")
        let badStoredSize = fixture(path: path, payload: bmp, lengthOverride: 12)
        expectFailure(badStoredSize, containing: "inconsistent lengths")
        let compressed = try WadArchive(data: fixture(path: path, payload: bmp, flags: 2))
        do {
            _ = try compressed.asset(path)
            fatalError("Compressed assets cannot be returned as plain BMP data")
        } catch WadArchive.WadError.unsupportedCompression(_) { }
        // Untrusted asset names must not be able to confuse lookup normalization.
        precondition(!wad.contains("../../Interface/FrontEnd/MenuBGpic.bmp"))
        print("PASS: WWAD signature, path lookup, stored image bytes, bounds, corrupt headers, and RNC refusal")
    }
}
