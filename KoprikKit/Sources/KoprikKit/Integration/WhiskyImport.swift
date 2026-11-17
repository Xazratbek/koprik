import Foundation

/// Bottles made by Whisky (com.isaacmarovitz.Whisky), which Ko'prik can take over.
public struct WhiskyBottle: Sendable, Equatable, Identifiable {
    public var name: String
    public var url: URL
    public var windowsVersion: WindowsVersion

    public var id: URL { url }
}

public enum WhiskyImport {
    public static var container: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.isaacmarovitz.Whisky", directoryHint: .isDirectory)
    }

    /// Bottles listed in Whisky's `BottleVM.plist`, plus any in its default
    /// folder that the list missed. Only folders that hold a Wine prefix count.
    public static func bottles(container: URL = container) -> [WhiskyBottle] {
        var urls: [URL] = []
        if let data = try? Data(contentsOf: container.appending(path: "BottleVM.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let paths = plist["paths"] as? [Any] {
            for entry in paths {
                // URLs are encoded either as a string or as {"relative": "file:///..."}.
                let string = (entry as? String) ?? ((entry as? [String: Any])?["relative"] as? String)
                if let string, let url = string.hasPrefix("file:") ? URL(string: string) : URL(fileURLWithPath: string) {
                    urls.append(url)
                }
            }
        }
        let defaultFolder = container.appending(path: "Bottles", directoryHint: .isDirectory)
        urls += (try? FileManager.default.contentsOfDirectory(at: defaultFolder, includingPropertiesForKeys: nil)) ?? []

        var seen: Set<String> = []
        return urls.compactMap { url in
            let key = url.standardizedFileURL.path
            guard seen.insert(key).inserted,
                  FileManager.default.fileExists(atPath: url.appending(path: "drive_c").path) else { return nil }
            return bottle(at: url)
        }
    }

    static func bottle(at url: URL) -> WhiskyBottle {
        var name = url.lastPathComponent
        var version = WindowsVersion.win10
        if let data = try? Data(contentsOf: url.appending(path: "Metadata.plist")),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            if let info = plist["info"] as? [String: Any], let stored = info["name"] as? String, !stored.isEmpty {
                name = stored
            }
            if let wine = plist["wineConfig"] as? [String: Any], let raw = wine["windowsVersion"] as? String,
               let parsed = WindowsVersion(rawValue: raw) {
                version = parsed
            }
        }
        return WhiskyBottle(name: name, url: url, windowsVersion: version)
    }
}

extension BottleStore {
    /// Copies a Whisky bottle into Ko'prik. The Whisky bottle is left as it
    /// was; on APFS the copy shares disk space with it until files change.
    public func importWhisky(_ source: WhiskyBottle, engine: Engine) throws -> Bottle {
        var name = source.name
        var counter = 2
        while (try? bottle(name)) != nil {
            name = "\(source.name) \(counter)"
            counter += 1
        }
        try paths.ensureDirectories()
        let config = BottleConfig(name: name, engineID: engine.id, windowsVersion: source.windowsVersion,
                                  notes: "Imported from Whisky (\(source.url.path))")
        let directory = paths.bottles.appending(path: config.id.uuidString, directoryHint: .isDirectory)
        let bottle = Bottle(config: config, directory: directory)
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: source.url, to: bottle.prefix)
            // Whisky's own files are not part of the Windows prefix.
            for leftover in ["Metadata.plist", "Program Settings"] {
                try? manager.removeItem(at: bottle.prefix.appending(path: leftover))
            }
            for folder in [bottle.logs, bottle.snapshots, bottle.programs] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            return try save(bottle)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }
}

extension BottleTools {
    /// Folders where Windows games keep saves and settings.
    static let saveFolders = [
        "Documents", "Saved Games", "AppData/Roaming", "AppData/Local", "AppData/LocalLow",
    ]

    /// Caches and runtime data inside those folders that are large and
    /// worthless in a backup.
    static let saveExclusions = [
        "*/Temp/*", "*/INetCache/*", "*/htmlcache/*", "*/Cache/*", "*/cache/*", "*/GPUCache/*",
        "*/Code Cache/*", "*/CrashDumps/*", "*/Microsoft/*", "*/Steam/htmlcache/*",
    ]

    /// Packs the Windows user folders that hold game saves into one archive.
    @discardableResult
    public func backupSaves(to folder: URL) async throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let users = bottle.driveC.appending(path: "users", directoryHint: .isDirectory)
        var members: [String] = []
        for user in (try? manager.contentsOfDirectory(atPath: users.path)) ?? [] where user != "Public" {
            for save in Self.saveFolders where manager.fileExists(atPath: users.appending(path: "\(user)/\(save)").path) {
                members.append("\(user)/\(save)")
            }
        }
        guard !members.isEmpty else { throw KoprikError.invalidArgument("No save folders found in \(bottle.name).") }

        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let safeName = bottle.name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        let archive = folder.appending(path: "\(String(safeName))-saves-\(stamp).tar.zst")
        var arguments = ["--zstd", "-cf", archive.path]
        for pattern in Self.saveExclusions { arguments += ["--exclude", pattern] }
        arguments += ["-C", users.path] + members
        try await ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/tar"), arguments: arguments)
        return archive
    }

    /// Puts saves from a backup back. Files in the backup replace current ones; others are kept.
    public func restoreSaves(from archive: URL) async throws {
        let users = bottle.driveC.appending(path: "users", directoryHint: .isDirectory)
        try await ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-xf", archive.path, "-C", users.path])
    }
}
