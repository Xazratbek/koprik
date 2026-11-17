import Foundation

/// A Windows shortcut (`.lnk`), as left in the Start Menu by installers.
///
/// Only the fields Ko'prik uses are read: where the shortcut points, its
/// arguments and its working directory.
public struct ShellLink: Sendable, Equatable {
    /// Windows path of the target, for example `C:\Program Files\App\app.exe`.
    public var targetPath: String?
    public var arguments: String?
    public var workingDirectory: String?
    public var description: String?
    public var iconLocation: String?

    public init?(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }

    public init?(data: Data) {
        // Header: size 0x4C followed by the shell link class identifier.
        guard data.count >= 76, PEFile.read32(data, 0) == 0x4C,
              let flags = PEFile.read32(data, 20) else { return nil }
        let hasIDList = flags & 0x01 != 0
        let hasLinkInfo = flags & 0x02 != 0
        let isUnicode = flags & 0x80 != 0
        var offset = 76

        if hasIDList {
            guard let size = PEFile.read16(data, offset) else { return nil }
            offset += 2 + Int(size)
        }

        if hasLinkInfo {
            guard let size = PEFile.read32(data, offset),
                  let headerSize = PEFile.read32(data, offset + 4),
                  let infoFlags = PEFile.read32(data, offset + 8) else { return nil }
            if infoFlags & 0x01 != 0 {
                // Prefer the Unicode copy of the path when the structure carries one.
                if headerSize >= 0x24, let unicodeOffset = PEFile.read32(data, offset + 28), unicodeOffset != 0 {
                    targetPath = Self.utf16String(data, at: offset + Int(unicodeOffset))
                }
                if targetPath == nil, let baseOffset = PEFile.read32(data, offset + 16), baseOffset != 0 {
                    targetPath = Self.ansiString(data, at: offset + Int(baseOffset))
                }
                // The remainder of the path, when the target sits below a shared root.
                if let suffixOffset = PEFile.read32(data, offset + 24), suffixOffset != 0,
                   let suffix = Self.ansiString(data, at: offset + Int(suffixOffset)), !suffix.isEmpty,
                   let base = targetPath {
                    targetPath = base.hasSuffix("\\") ? base + suffix : base + "\\" + suffix
                }
            }
            offset += Int(size)
        }

        // String data, in a fixed order, each present only when its flag is set.
        func nextString(_ flag: UInt32) -> String? {
            guard flags & flag != 0, let count = PEFile.read16(data, offset) else { return nil }
            let length = Int(count) * (isUnicode ? 2 : 1)
            let start = offset + 2
            offset = start + length
            guard start + length <= data.count else { return nil }
            let bytes = data.subdata(in: (data.startIndex + start)..<(data.startIndex + start + length))
            return isUnicode ? String(data: bytes, encoding: .utf16LittleEndian) : String(data: bytes, encoding: .windowsCP1252)
        }
        description = nextString(0x04)
        let relativePath = nextString(0x08)
        workingDirectory = nextString(0x10)
        arguments = nextString(0x20)
        iconLocation = nextString(0x40)

        if targetPath == nil, let relativePath, let workingDirectory, !relativePath.isEmpty {
            // No absolute path stored; fall back to the file name inside the working directory.
            let name = relativePath.split(separator: "\\").last.map(String.init) ?? relativePath
            targetPath = workingDirectory.hasSuffix("\\") ? workingDirectory + name : workingDirectory + "\\" + name
        }
        if targetPath == nil { return nil }
    }

    private static func ansiString(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        let bytes = data[(data.startIndex + offset)...].prefix { $0 != 0 }
        return String(data: Data(bytes), encoding: .windowsCP1252)
    }

    private static func utf16String(_ data: Data, at offset: Int) -> String? {
        guard offset >= 0, offset < data.count else { return nil }
        var units: [UInt16] = []
        var position = offset
        while let unit = PEFile.read16(data, position), unit != 0, units.count < 1024 {
            units.append(unit)
            position += 2
        }
        return units.isEmpty ? nil : String(decoding: units, as: UTF16.self)
    }
}

/// Translates between Windows paths inside a bottle and files on the Mac.
public enum WindowsPath {
    /// Resolves `C:\Program Files\App\app.exe` to the file inside the bottle.
    ///
    /// Drive letters go through `dosdevices`, the folder of symbolic links
    /// where Wine keeps its drive map, so mapped drives resolve too.
    public static func hostURL(for windowsPath: String, prefix: URL) -> URL? {
        let path = windowsPath.replacingOccurrences(of: "/", with: "\\")
        guard path.count >= 2, path[path.index(after: path.startIndex)] == ":",
              let letter = path.first, letter.isLetter else { return nil }
        let drive = prefix
            .appending(path: "dosdevices", directoryHint: .isDirectory)
            .appending(path: "\(letter.lowercased()):", directoryHint: .isDirectory)
        let components = path.dropFirst(2).split(separator: "\\").map(String.init)
        return components.reduce(drive) { $0.appending(path: $1) }.resolvingSymlinksInPath()
    }

    /// Converts a file inside the bottle's C: drive to its Windows path.
    public static func windowsPath(for url: URL, prefix: URL) -> String? {
        let driveC = prefix.appending(path: "drive_c", directoryHint: .isDirectory).standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(driveC) else { return nil }
        let rest = path.dropFirst(driveC.count).split(separator: "/").joined(separator: "\\")
        return "C:\\" + rest
    }
}
