import Foundation

/// Reads the parts of a Windows executable that Ko'prik needs: its
/// architecture, the DLLs it imports and its icon.
///
/// Every read is bounds-checked, because the files come from anywhere and a
/// damaged or hostile executable must never crash the app.
public struct PEFile: Sendable {
    public enum Architecture: String, Sendable {
        case x86, x86_64, arm64, unknown
    }

    public let architecture: Architecture
    public let is64Bit: Bool

    private let data: Data
    private let sections: [Section]
    private let importDirectory: (rva: UInt32, size: UInt32)?
    private let resourceDirectory: (rva: UInt32, size: UInt32)?

    private struct Section {
        let virtualAddress: UInt32
        let virtualSize: UInt32
        let rawOffset: UInt32
        let rawSize: UInt32
    }

    /// Returns `nil` when the file is not a PE executable.
    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        self.init(data: data)
    }

    public init?(data: Data) {
        self.data = data
        guard data.count > 0x40, Self.read16(data, 0) == 0x5A4D else { return nil } // "MZ"
        guard let peOffset32 = Self.read32(data, 0x3C) else { return nil }
        let peOffset = Int(peOffset32)
        guard Self.read32(data, peOffset) == 0x0000_4550 else { return nil } // "PE\0\0"

        let coff = peOffset + 4
        guard let machine = Self.read16(data, coff),
              let sectionCount = Self.read16(data, coff + 2),
              let optionalSize = Self.read16(data, coff + 16) else { return nil }
        architecture = switch machine {
        case 0x014C: .x86
        case 0x8664: .x86_64
        case 0xAA64: .arm64
        default: .unknown
        }

        let optional = coff + 20
        guard let magic = Self.read16(data, optional) else { return nil }
        is64Bit = magic == 0x20B
        let directoryCountOffset = optional + (is64Bit ? 108 : 92)
        let directories = optional + (is64Bit ? 112 : 96)
        let directoryCount = Int(Self.read32(data, directoryCountOffset) ?? 0)

        func directory(_ index: Int) -> (UInt32, UInt32)? {
            guard index < directoryCount,
                  let rva = Self.read32(data, directories + index * 8),
                  let size = Self.read32(data, directories + index * 8 + 4),
                  rva != 0 else { return nil }
            return (rva, size)
        }
        importDirectory = directory(1)
        resourceDirectory = directory(2)

        var parsed: [Section] = []
        let table = optional + Int(optionalSize)
        for index in 0..<min(Int(sectionCount), 96) {
            let base = table + index * 40
            guard let virtualSize = Self.read32(data, base + 8),
                  let virtualAddress = Self.read32(data, base + 12),
                  let rawSize = Self.read32(data, base + 16),
                  let rawOffset = Self.read32(data, base + 20) else { break }
            parsed.append(Section(virtualAddress: virtualAddress, virtualSize: virtualSize, rawOffset: rawOffset, rawSize: rawSize))
        }
        sections = parsed
    }

    // MARK: Imports

    /// Lowercased names of the DLLs listed in the import table, for example `d3d11.dll`.
    public var importedLibraries: [String] {
        guard let importDirectory, var offset = fileOffset(rva: importDirectory.rva) else { return [] }
        var names: [String] = []
        for _ in 0..<512 {
            guard let lookup = Self.read32(data, offset),
                  let nameRVA = Self.read32(data, offset + 12),
                  let thunk = Self.read32(data, offset + 16) else { break }
            if lookup == 0 && nameRVA == 0 && thunk == 0 { break }
            if let nameOffset = fileOffset(rva: nameRVA), let name = cString(at: nameOffset) {
                names.append(name.lowercased())
            }
            offset += 20
        }
        return names
    }

    // MARK: Icon

    /// The program's main icon as the bytes of a `.ico` file, which `NSImage` can open.
    public var iconFileData: Data? {
        guard let resourceDirectory, let root = fileOffset(rva: resourceDirectory.rva) else { return nil }

        // Resource tree: type -> name -> language -> data.
        guard let groups = entries(ofDirectoryAt: root, root: root).first(where: { $0.id == 14 && $0.isDirectory }),
              let firstGroup = entries(ofDirectoryAt: root + groups.offset, root: root).first,
              let group = leafData(of: firstGroup, root: root),
              group.count >= 6 else { return nil }

        let count = Int(Self.read16(group, 4) ?? 0)
        guard count > 0, count <= 64, group.count >= 6 + count * 14 else { return nil }

        let iconDirectory = entries(ofDirectoryAt: root, root: root).first(where: { $0.id == 3 && $0.isDirectory })
        let iconEntries = iconDirectory.map { entries(ofDirectoryAt: root + $0.offset, root: root) } ?? []

        var headers: [Data] = []
        var images: [Data] = []
        for index in 0..<count {
            let base = 6 + index * 14
            guard let iconID = Self.read16(group, base + 12),
                  let entry = iconEntries.first(where: { $0.id == UInt32(iconID) }),
                  let image = leafData(of: entry, root: root) else { continue }
            headers.append(group.subdata(in: (group.startIndex + base)..<(group.startIndex + base + 8)))
            images.append(image)
        }
        guard !images.isEmpty else { return nil }

        var file = Data()
        file.append(contentsOf: [0, 0, 1, 0])
        Self.append16(&file, UInt16(images.count))
        var imageOffset = 6 + images.count * 16
        for (header, image) in zip(headers, images) {
            file.append(header)
            Self.append32(&file, UInt32(image.count))
            Self.append32(&file, UInt32(imageOffset))
            imageOffset += image.count
        }
        images.forEach { file.append($0) }
        return file
    }

    private struct ResourceEntry {
        let id: UInt32?
        let offset: Int
        let isDirectory: Bool
    }

    private func entries(ofDirectoryAt offset: Int, root: Int) -> [ResourceEntry] {
        guard let named = Self.read16(data, offset + 12), let identified = Self.read16(data, offset + 14) else { return [] }
        let total = min(Int(named) + Int(identified), 4096)
        var result: [ResourceEntry] = []
        for index in 0..<total {
            let base = offset + 16 + index * 8
            guard let name = Self.read32(data, base), let target = Self.read32(data, base + 4) else { break }
            result.append(ResourceEntry(
                id: name & 0x8000_0000 == 0 ? name : nil,
                offset: Int(target & 0x7FFF_FFFF),
                isDirectory: target & 0x8000_0000 != 0
            ))
        }
        return result
    }

    /// Follows an entry down through its language level to the bytes it names.
    private func leafData(of entry: ResourceEntry, root: Int) -> Data? {
        var current = entry
        for _ in 0..<3 where current.isDirectory {
            guard let next = entries(ofDirectoryAt: root + current.offset, root: root).first else { return nil }
            current = next
        }
        guard !current.isDirectory,
              let rva = Self.read32(data, root + current.offset),
              let size = Self.read32(data, root + current.offset + 4),
              let start = fileOffset(rva: rva),
              size > 0, size < 16 << 20, start + Int(size) <= data.count else { return nil }
        return data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + Int(size)))
    }

    // MARK: Low-level reading

    private func fileOffset(rva: UInt32) -> Int? {
        for section in sections {
            let size = max(section.virtualSize, section.rawSize)
            if rva >= section.virtualAddress, rva - section.virtualAddress < size {
                let offset = Int(rva - section.virtualAddress) + Int(section.rawOffset)
                return offset < data.count ? offset : nil
            }
        }
        return nil
    }

    private func cString(at offset: Int, limit: Int = 260) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let start = data.startIndex + offset
        let end = min(start + limit, data.endIndex)
        let bytes = data[start..<end].prefix { $0 != 0 }
        return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
    }

    static func read16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt16(data[start]) | UInt16(data[start + 1]) << 8
    }

    static func read32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        let start = data.startIndex + offset
        return UInt32(data[start]) | UInt32(data[start + 1]) << 8
            | UInt32(data[start + 2]) << 16 | UInt32(data[start + 3]) << 24
    }

    static func append16(_ data: inout Data, _ value: UInt16) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8(value >> 8)])
    }

    static func append32(_ data: inout Data, _ value: UInt32) {
        data.append(contentsOf: [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8(value >> 24)])
    }
}
