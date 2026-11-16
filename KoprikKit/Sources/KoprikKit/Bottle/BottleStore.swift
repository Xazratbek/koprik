import Foundation

/// Creates, lists, copies, snapshots and removes bottles under `AppPaths.bottles`.
public actor BottleStore {
    public let paths: AppPaths

    public init(paths: AppPaths = .default) {
        self.paths = paths
    }

    // MARK: Reading

    public func all() throws -> [Bottle] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.bottles.path) else { return [] }
        return try manager
            .contentsOfDirectory(at: paths.bottles, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .compactMap { directory in
                guard let config = try? JSONFile.read(BottleConfig.self, from: directory.appending(path: Bottle.configName))
                else { return nil }
                return Bottle(config: config, directory: directory)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Finds a bottle by name (case-insensitive) or by UUID.
    public func bottle(_ nameOrID: String) throws -> Bottle {
        let bottles = try all()
        if let match = bottles.first(where: { $0.name.compare(nameOrID, options: .caseInsensitive) == .orderedSame })
            ?? bottles.first(where: { $0.id.uuidString.compare(nameOrID, options: .caseInsensitive) == .orderedSame }) {
            return match
        }
        throw KoprikError.bottleNotFound(nameOrID)
    }

    // MARK: Creating

    /// Creates a bottle and lets Wine populate its prefix.
    ///
    /// If Wine fails, the half-made bottle is removed so nothing broken is left behind.
    public func create(
        name: String,
        engine: Engine,
        windowsVersion: WindowsVersion = .win10,
        settings: LaunchSettings = LaunchSettings()
    ) async throws -> Bottle {
        try ensureNameIsFree(name)
        try paths.ensureDirectories()

        let config = BottleConfig(name: name, engineID: engine.id, windowsVersion: windowsVersion, settings: settings)
        let directory = paths.bottles.appending(path: config.id.uuidString, directoryHint: .isDirectory)
        var bottle = Bottle(config: config, directory: directory)
        let manager = FileManager.default

        do {
            for folder in [bottle.prefix, bottle.logs, bottle.snapshots, bottle.programs] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            bottle = try save(bottle)
            try await initializePrefix(of: bottle, engine: engine)
            return bottle
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    private func initializePrefix(of bottle: Bottle, engine: Engine) async throws {
        let runner = WineRunner(engine: engine)
        let environment = WineEnvironment.build(
            engine: engine,
            prefix: bottle.prefix,
            settings: LaunchSettings.resolve([engine.defaultSettings, bottle.config.settings])
        )
        let log = bottle.newLogURL(label: "create")

        let bootStatus = try await runner.run(["wineboot", "--init"], environment: environment, logURL: log)
        guard bootStatus == 0 else {
            throw KoprikError.commandFailed(command: "wineboot --init", status: bootStatus, output: Self.tail(of: log))
        }
        // wineboot returns before the prefix is fully written; wait for the server to go idle.
        try await runner.wineserver(["-w"], environment: environment, logURL: log)

        let versionStatus = try await runner.run(
            ["winecfg", "-v", bottle.config.windowsVersion.rawValue], environment: environment, logURL: log
        )
        guard versionStatus == 0 else {
            throw KoprikError.commandFailed(command: "winecfg -v", status: versionStatus, output: Self.tail(of: log))
        }
        try await runner.wineserver(["-w"], environment: environment, logURL: log)
    }

    // MARK: Changing

    /// Writes the bottle's settings and returns the bottle as stored.
    @discardableResult
    public func save(_ bottle: Bottle) throws -> Bottle {
        var saved = bottle
        saved.config = try JSONFile.write(bottle.config, to: bottle.directory.appending(path: Bottle.configName))
        return saved
    }

    public func rename(_ bottle: Bottle, to newName: String) throws -> Bottle {
        try ensureNameIsFree(newName, except: bottle.id)
        var renamed = bottle
        renamed.config.name = newName
        return try save(renamed)
    }

    /// Copies a bottle under a new name. On APFS the copy is a copy-on-write
    /// clone: instant, and it uses no extra disk space until files diverge.
    public func duplicate(_ bottle: Bottle, as newName: String) throws -> Bottle {
        try ensureNameIsFree(newName)
        var config = bottle.config
        config.id = UUID()
        config.name = newName
        config.createdAt = .now

        let directory = paths.bottles.appending(path: config.id.uuidString, directoryHint: .isDirectory)
        let copy = Bottle(config: config, directory: directory)
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: bottle.prefix, to: copy.prefix)
            for folder in [copy.logs, copy.snapshots, copy.programs] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            if manager.fileExists(atPath: bottle.programs.path) {
                try manager.removeItem(at: copy.programs)
                try manager.copyItem(at: bottle.programs, to: copy.programs)
            }
            return try save(copy)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    /// Removes a bottle. By default it goes to the Trash, so a mistake can be undone.
    public func delete(_ bottle: Bottle, permanently: Bool = false) throws {
        if permanently {
            try FileManager.default.removeItem(at: bottle.directory)
        } else {
            try FileManager.default.trashItem(at: bottle.directory, resultingItemURL: nil)
        }
    }

    // MARK: Snapshots

    public func snapshots(of bottle: Bottle) throws -> [BottleSnapshot] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: bottle.snapshots.path) else { return [] }
        return try manager
            .contentsOfDirectory(at: bottle.snapshots, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .compactMap { try? JSONFile.read(BottleSnapshot.self, from: $0.appending(path: BottleSnapshot.infoName)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Saves the bottle's current prefix. Nothing in the bottle should be running.
    @discardableResult
    public func snapshot(_ bottle: Bottle, label: String) throws -> BottleSnapshot {
        let manager = FileManager.default
        let snapshot = BottleSnapshot(id: UUID().uuidString.lowercased(), label: label)
        let directory = bottle.snapshots.appending(path: snapshot.id, directoryHint: .isDirectory)
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try manager.copyItem(at: bottle.prefix, to: directory.appending(path: "prefix", directoryHint: .isDirectory))
            return try JSONFile.write(snapshot, to: directory.appending(path: BottleSnapshot.infoName))
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    /// Replaces the bottle's prefix with a snapshot. Nothing in the bottle should be running.
    ///
    /// The current prefix is set aside first and only discarded once the
    /// snapshot is in place, so a failure part-way leaves the bottle as it was.
    public func restore(_ bottle: Bottle, snapshotID: String) throws {
        let manager = FileManager.default
        let saved = bottle.snapshots
            .appending(path: snapshotID, directoryHint: .isDirectory)
            .appending(path: "prefix", directoryHint: .isDirectory)
        guard manager.fileExists(atPath: saved.path) else { throw KoprikError.snapshotNotFound(snapshotID) }

        let aside = bottle.directory.appending(path: ".prefix-replaced-\(UUID().uuidString)", directoryHint: .isDirectory)
        try manager.moveItem(at: bottle.prefix, to: aside)
        do {
            try manager.copyItem(at: saved, to: bottle.prefix)
        } catch {
            try? manager.removeItem(at: bottle.prefix)
            try manager.moveItem(at: aside, to: bottle.prefix)
            throw error
        }
        try? manager.removeItem(at: aside)
    }

    public func deleteSnapshot(_ bottle: Bottle, snapshotID: String) throws {
        let directory = bottle.snapshots.appending(path: snapshotID, directoryHint: .isDirectory)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw KoprikError.snapshotNotFound(snapshotID)
        }
        try FileManager.default.removeItem(at: directory)
    }

    // MARK: Helpers

    private func ensureNameIsFree(_ name: String, except id: UUID? = nil) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KoprikError.invalidArgument("A bottle needs a name.") }
        let taken = try all().contains {
            $0.id != id && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }
        if taken { throw KoprikError.bottleNameTaken(trimmed) }
    }

    /// The last lines of a log, for error messages.
    static func tail(of log: URL, lines: Int = 15) -> String {
        guard let text = try? String(contentsOf: log, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(lines).joined(separator: "\n")
    }
}
