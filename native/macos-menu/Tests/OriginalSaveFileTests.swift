import Foundation

@main struct OriginalSaveFileTests {
    static func main() throws {
        func makeSave(count: Int, completed: [Int] = []) -> Data {
            var bytes = [UInt8](repeating: 0, count:
                OriginalSaveFile.headerSize + count * OriginalSaveFile.missionSize)
            func put32(_ value: UInt32, at position: Int) {
                for i in 0..<4 { bytes[position + i] = UInt8(truncatingIfNeeded: value >> (i * 8)) }
            }
            put32(5, at: 0x04) // Original default music level
            put32(7, at: 0x08) // Original default sound level
            put32(UInt32(count), at: 0x18)
            for completedIndex in completed {
                put32(1, at: OriginalSaveFile.headerSize +
                      completedIndex * OriginalSaveFile.missionSize)
            }
            return Data(bytes)
        }
        let saveBytes = makeSave(count: 3, completed: [0, 2])
        let save = try OriginalSaveFile(data: saveBytes, expectedMissionCount: 3)
        precondition(save.missionCount == 3)
        precondition(save.completedLevelIndices == Set([0, 2]))
        precondition(save.musicVolume == 5 && save.soundVolume == 7)

        func fails(_ description: String, _ bytes: Data, expected: Int? = nil) {
            do {
                _ = try OriginalSaveFile(data: bytes, expectedMissionCount: expected)
                preconditionFailure("Invalid save accepted: \(description)")
            } catch is OriginalSaveFile.SaveError {} catch {
                preconditionFailure("Unexpected save error: \(error)")
            }
        }
        fails("too-short header", Data(saveBytes.prefix(0xa0)))
        fails("truncated mission record", Data(saveBytes.dropLast()))
        fails("different mission count", saveBytes, expected: 4)
        var corrupt = [UInt8](saveBytes)
        corrupt[0x18] = 255
        fails("absurd level count", Data(corrupt))

        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(
            "rr-save-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: temp) }
        let savesDir = temp.appendingPathComponent("Saves", isDirectory: true)
        try fm.createDirectory(at: savesDir, withIntermediateDirectories: true)
        try saveBytes.write(to: savesDir.appendingPathComponent("0.sav"))
        try makeSave(count: 2).write(to: savesDir.appendingPathComponent("1.sav"))
        try Data([1, 2, 3]).write(to: savesDir.appendingPathComponent("2.sav"))

        let wad = temp.appendingPathComponent("LegoRR0.wad")
        let slots = OriginalSaveCatalog(selectedWadURL: wad, expectedMissionCount: 3).slots
        precondition(slots.count == 5)
        precondition(slots.map(\.number) == [1, 2, 3, 4, 5])
        switch slots[0].state {
        case .valid(let loaded):
            precondition(loaded.completedLevelIndices == Set([0, 2]))
        default: preconditionFailure("Did not load original save slot 1")
        }
        switch slots[1].state {
        case .incompatible: break
        default: preconditionFailure("Did not reject mission mismatch")
        }
        switch slots[2].state {
        case .unreadable: break
        default: preconditionFailure("Did not reject short save slot")
        }
        for slot in slots[3...4] {
            switch slot.state {
            case .empty: break
            default: preconditionFailure("Nonexistent save slot should be empty")
            }
        }
        print("PASS: original .sav format, completed flags, five slots and invalid data rejection")
    }
}
