import Foundation

/// Read-only decoder for the original PC LEGO Rock Raiders 32-bit .sav files.
/// Front_Save_ReadSaveFile and Front_Save_WriteSaveFiles in
/// src/openlrr/game/front/FrontEnd.cpp read/write 0xb0 bytes of SaveData
/// followed by missionsCount × 0x3190-byte SaveReward records.
/// This deliberately never writes, upgrades, or repairs original saves.
struct OriginalSaveFile {
    enum SaveError: Error, CustomStringConvertible {
        case invalid(String)

        var description: String {
            switch self {
            case .invalid(let detail): return "Invalid original Rock Raiders save: \(detail)"
            }
        }
    }

    static let headerSize = 0xb0
    static let missionSize = 0x3190
    static let maxMissionCount = 150

    let missionCount: Int
    let completedLevelIndices: Set<Int>
    let soundVolume: Int
    let musicVolume: Int

    init(data: Data, expectedMissionCount: Int? = nil) throws {
        guard data.count >= Self.headerSize else {
            throw SaveError.invalid("truncated 0xb0-byte save header")
        }
        func u32(_ position: Int) -> Int {
            Int(data[position]) | (Int(data[position + 1]) << 8) |
            (Int(data[position + 2]) << 16) | (Int(data[position + 3]) << 24)
        }

        let count = u32(0x18)
        guard (0...Self.maxMissionCount).contains(count),
              data.count >= Self.headerSize + (count * Self.missionSize) else {
            throw SaveError.invalid("invalid mission count or truncated rewards")
        }
        if let expectedMissionCount, count != expectedMissionCount {
            throw SaveError.invalid("mission count \(count) does not match game \(expectedMissionCount)")
        }

        self.missionCount = count
        self.musicVolume = u32(0x04)
        self.soundVolume = u32(0x08)
        var completed = Set<Int>()
        for mission in 0..<count {
            let offset = Self.headerSize + mission * Self.missionSize
            // SaveReward.flags bit 0 is SAVEREWARD_FLAG_COMPLETED.
            if (u32(offset) & 0x1) != 0 { completed.insert(mission) }
        }
        self.completedLevelIndices = completed
    }
}

/// Finds up to five visible retail save slots beside a selected game/WAD and
/// under known installed directories. The user never has to select individual
/// .sav files, and the native application never changes them.
struct OriginalSaveCatalog {
    enum SlotState {
        case empty
        case valid(OriginalSaveFile)
        case incompatible
        case unreadable
    }

    struct Slot {
        let number: Int
        let state: SlotState
        let source: URL?
    }

    let slots: [Slot]

    init(selectedWadURL: URL, expectedMissionCount: Int,
         additionalInstallRoots: [URL] = [],
         fileManager: FileManager = .default) {
        let directory = selectedWadURL.deletingLastPathComponent()
        let roots = [directory, directory.deletingLastPathComponent()] +
                    additionalInstallRoots
        var result: [Slot] = []
        for slot in 0..<5 {
            var foundURL: URL?
            for root in roots {
                let parent = root.appendingPathComponent("Saves", isDirectory: true)
                guard let names = try? fileManager.contentsOfDirectory(atPath: parent.path),
                      let name = names.first(where: { $0.caseInsensitiveCompare("\(slot).sav") == .orderedSame })
                else { continue }
                foundURL = parent.appendingPathComponent(name)
                break
            }
            guard let url = foundURL else {
                result.append(Slot(number: slot + 1, state: .empty, source: nil))
                continue
            }
            guard let attrs = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  attrs.isRegularFile == true, let length = attrs.fileSize,
                  (OriginalSaveFile.headerSize...20_000_000).contains(length),
                  let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                result.append(Slot(number: slot + 1, state: .unreadable, source: url))
                continue
            }
            do {
                let save = try OriginalSaveFile(data: data,
                                                expectedMissionCount: expectedMissionCount)
                result.append(Slot(number: slot + 1, state: .valid(save), source: url))
            } catch {
                result.append(Slot(number: slot + 1, state: .incompatible, source: url))
            }
        }
        self.slots = result
    }
}
