import Foundation

/// Maintenance actions on a bottle: registry switches, Windows tools,
/// archives and disk usage.
public struct BottleTools: Sendable {
    public let bottle: Bottle
    public let engine: Engine

    public init(bottle: Bottle, engine: Engine) {
        self.bottle = bottle
        self.engine = engine
    }

    private var environment: [String: String] {
        WineEnvironment.build(
            engine: engine, prefix: bottle.prefix,
            settings: LaunchSettings.resolve([engine.defaultSettings, bottle.config.settings])
        )
    }

    private func wine(_ arguments: [String], label: String) async throws -> Int32 {
        try await WineRunner(engine: engine).run(arguments, environment: environment, logURL: bottle.newLogURL(label: label))
    }

    // MARK: Registry

    /// Writes a string value, creating the key when needed.
    public func setRegistryValue(key: String, name: String, value: String, type: String = "REG_SZ") async throws {
        let status = try await wine(["reg", "add", key, "/v", name, "/t", type, "/d", value, "/f"], label: "reg")
        guard status == 0 else {
            throw KoprikError.commandFailed(command: "reg add \(key) \(name)", status: status, output: "")
        }
    }

    public func deleteRegistryValue(key: String, name: String) async throws {
        _ = try await wine(["reg", "delete", key, "/v", name, "/f"], label: "reg")
    }

    static let macDriverKey = "HKCU\\Software\\Wine\\Mac Driver"

    /// Renders at the display's full pixel resolution instead of scaled points.
    /// Sharper, and heavier on the GPU.
    public func setRetinaMode(_ enabled: Bool) async throws {
        try await setRegistryValue(key: Self.macDriverKey, name: "RetinaMode", value: enabled ? "Y" : "N")
        // Windows programs need a matching DPI or their text becomes tiny.
        try await setRegistryValue(key: "HKCU\\Control Panel\\Desktop", name: "LogPixels", value: enabled ? "192" : "96", type: "REG_DWORD")
    }

    /// Makes the Mac's Command key act as Ctrl and Option as Alt, so Windows
    /// shortcuts sit where the fingers expect them.
    public func setMacKeyboardMapping(commandIsControl: Bool, optionIsAlt: Bool) async throws {
        for name in ["LeftCommandIsCtrl", "RightCommandIsCtrl"] {
            try await setRegistryValue(key: Self.macDriverKey, name: name, value: commandIsControl ? "Y" : "N")
        }
        for name in ["LeftOptionIsAlt", "RightOptionIsAlt"] {
            try await setRegistryValue(key: Self.macDriverKey, name: name, value: optionIsAlt ? "Y" : "N")
        }
    }

    public func setWindowsVersion(_ version: WindowsVersion) async throws {
        let status = try await wine(["winecfg", "-v", version.rawValue], label: "winecfg")
        guard status == 0 else {
            throw KoprikError.commandFailed(command: "winecfg -v \(version.rawValue)", status: status, output: "")
        }
    }

    /// Restarts the Windows session, as installers ask for with "please reboot".
    public func simulateReboot() async throws {
        _ = try await wine(["wineboot", "--restart"], label: "reboot")
    }

    // MARK: Drives

    /// Drive letters and where they point on the Mac.
    public func drives() -> [(letter: String, target: URL)] {
        let devices = bottle.prefix.appending(path: "dosdevices", directoryHint: .isDirectory)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: devices.path)) ?? []
        return names
            .filter { $0.count == 2 && $0.hasSuffix(":") }
            .sorted()
            .map { ($0.uppercased(), devices.appending(path: $0).resolvingSymlinksInPath()) }
    }

    public func setDrive(_ letter: Character, to target: URL?) throws {
        let link = bottle.prefix.appending(path: "dosdevices/\(letter.lowercased()):")
        let manager = FileManager.default
        guard letter.lowercased() != "c" else {
            throw KoprikError.invalidArgument("Drive C: is the bottle itself and cannot be remapped.")
        }
        if (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil { try manager.removeItem(at: link) }
        if let target { try manager.createSymbolicLink(at: link, withDestinationURL: target) }
    }

    /// Cuts the bottle off from the rest of the Mac: removes every drive but
    /// C:, and replaces the links from the Windows user folders (Desktop,
    /// Documents, ...) to the real ones with plain folders inside the bottle.
    public func restrictFileAccess() throws {
        let manager = FileManager.default
        for drive in drives() where drive.letter != "C:" {
            try setDrive(Character(drive.letter.prefix(1).lowercased()), to: nil)
        }
        let users = bottle.driveC.appending(path: "users", directoryHint: .isDirectory)
        for user in (try? manager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            for entry in (try? manager.contentsOfDirectory(at: user, includingPropertiesForKeys: nil)) ?? []
            where (try? manager.destinationOfSymbolicLink(atPath: entry.path)) != nil {
                try manager.removeItem(at: entry)
                try manager.createDirectory(at: entry, withIntermediateDirectories: true)
            }
        }
    }

    // MARK: Archive and size

    /// Packs the bottle into one compressed file that can be moved to another Mac.
    public func export(to archive: URL) async throws {
        try await ProcessRunner.runChecked(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["--zstd", "-cf", archive.path, "--exclude", "snapshots", "--exclude", "logs",
                        "-C", bottle.directory.deletingLastPathComponent().path, bottle.directory.lastPathComponent]
        )
    }

    /// Bytes the bottle occupies, snapshots included. Cloned files are counted
    /// in full, so the true cost on disk can be lower.
    public func diskUsage() async -> Int64 {
        guard let result = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/du"), arguments: ["-sk", bottle.directory.path]),
              let kilobytes = result.stdout.split(separator: "\t").first.flatMap({ Int64($0) }) else { return 0 }
        return kilobytes * 1024
    }
}

extension BottleStore {
    /// Unpacks an archive made by `BottleTools.export` as a new bottle.
    public func importArchive(_ archive: URL, name: String? = nil) async throws -> Bottle {
        try paths.ensureDirectories()
        let manager = FileManager.default
        let staging = paths.bottles.appending(path: ".import-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? manager.removeItem(at: staging) }
        try await Archive.extract(archive, to: staging)

        guard let unpacked = try manager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil).first,
              var config = try? JSONFile.read(BottleConfig.self, from: unpacked.appending(path: Bottle.configName)) else {
            throw KoprikError.invalidArgument("\(archive.lastPathComponent) is not a Ko'prik bottle archive.")
        }
        // A fresh identity, so importing an archive of a bottle that still exists is safe.
        config.id = UUID()
        config.createdAt = .now
        var wanted = name ?? config.name
        var counter = 2
        while (try? bottle(wanted)) != nil {
            wanted = "\(name ?? config.name) \(counter)"
            counter += 1
        }
        config.name = wanted

        let directory = paths.bottles.appending(path: config.id.uuidString, directoryHint: .isDirectory)
        try manager.moveItem(at: unpacked, to: directory)
        let imported = Bottle(config: config, directory: directory)
        for folder in [imported.logs, imported.snapshots, imported.programs] {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return try save(imported)
    }
}
