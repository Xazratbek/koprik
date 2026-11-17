import Foundation

/// Installs, lists and removes Wine builds under `AppPaths.engines`.
///
/// Several engines live side by side and each bottle names the one it uses, so
/// a new engine can be tried without touching bottles that work today.
public actor EngineStore {
    public let paths: AppPaths

    public init(paths: AppPaths = .default) {
        self.paths = paths
    }

    // MARK: Reading

    public func installed() throws -> [Engine] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: paths.engines.path) else { return [] }
        return try manager
            .contentsOfDirectory(at: paths.engines, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .compactMap { directory in
                let manifestURL = directory.appending(path: Engine.manifestName)
                guard let manifest = try? JSONFile.read(EngineManifest.self, from: manifestURL) else { return nil }
                return Engine(manifest: manifest, directory: directory)
            }
            .sorted { $0.manifest.installedAt > $1.manifest.installedAt }
    }

    public func engine(id: String) throws -> Engine {
        guard let engine = try installed().first(where: { $0.id == id }) else {
            throw KoprikError.engineNotFound(id)
        }
        return engine
    }

    /// The engine to use when the caller did not name one: the newest
    /// D3DMetal-capable build, otherwise the newest of any kind.
    public func preferred() throws -> Engine? {
        let engines = try installed()
        return engines.first(where: \.manifest.d3dmetalCapable) ?? engines.first
    }

    // MARK: Installing

    /// Downloads, verifies and installs an engine from a remote source.
    public func install(
        _ source: EngineSource,
        progress: (@Sendable (DownloadProgress) -> Void)? = nil
    ) async throws -> Engine {
        guard let archiveURL = source.archiveURL else {
            throw KoprikError.invalidArgument("Use importLocal(at:) for engines that are already on disk.")
        }
        let id = source.defaultID
        if (try? engine(id: id)) != nil { throw KoprikError.engineAlreadyInstalled(id) }

        try paths.ensureDirectories()
        let archive = paths.downloads.appending(path: "\(id)-\(archiveURL.lastPathComponent)")
        try await Downloader.download(archiveURL, to: archive, progress: progress)
        defer { try? FileManager.default.removeItem(at: archive) }

        if let expected = try await expectedChecksum(for: source) {
            let actual = try Checksum.sha256(of: archive)
            guard actual == expected else {
                throw KoprikError.checksumMismatch(expected: expected, actual: actual)
            }
        }
        return try await installArchive(archive, id: id, name: source.displayName, source: source)
    }

    /// Installs an engine from a tar archive or an already-unpacked Wine tree on disk.
    public func importLocal(at url: URL, id: String? = nil, name: String? = nil) async throws -> Engine {
        let source = EngineSource.local(path: url.path)
        let engineID = id ?? source.defaultID
        if (try? engine(id: engineID)) != nil { throw KoprikError.engineAlreadyInstalled(engineID) }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw KoprikError.invalidArgument("Nothing exists at \(url.path).")
        }
        try paths.ensureDirectories()
        if isDirectory.boolValue {
            let staging = stagingDirectory()
            // On APFS this is a copy-on-write clone, so it is instant and takes no extra space.
            try FileManager.default.copyItem(at: url, to: staging)
            return try await finishInstall(staging: staging, id: engineID, name: name ?? source.displayName, source: source)
        }
        return try await installArchive(url, id: engineID, name: name ?? source.displayName, source: source)
    }

    public func remove(id: String) throws {
        let engine = try engine(id: id)
        try FileManager.default.removeItem(at: engine.directory)
    }

    // MARK: Internals

    private func installArchive(_ archive: URL, id: String, name: String, source: EngineSource) async throws -> Engine {
        let staging = stagingDirectory()
        do {
            try await Archive.extract(archive, to: staging)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return try await finishInstall(staging: staging, id: id, name: name, source: source)
    }

    private func finishInstall(staging: URL, id: String, name: String, source: EngineSource) async throws -> Engine {
        let manager = FileManager.default
        do {
            guard let wineRoot = Self.locateWineRoot(in: staging) else {
                throw KoprikError.wineBinaryNotFound(staging)
            }
            await Archive.removeQuarantine(at: staging)

            let relativeRoot = wineRoot.standardizedFileURL.path
                .dropFirst(staging.standardizedFileURL.path.count)
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            var manifest = EngineManifest(
                id: id,
                name: name,
                source: source,
                d3dmetalCapable: source.d3dmetalCapable,
                components: Self.bundledComponents(in: staging),
                wineRoot: relativeRoot
            )

            let destination = paths.engines.appending(path: id, directoryHint: .isDirectory)
            manifest = try JSONFile.write(manifest, to: staging.appending(path: Engine.manifestName))
            try manager.moveItem(at: staging, to: destination)

            // Asking Wine for its version doubles as a check that the build runs at all.
            var engine = Engine(manifest: manifest, directory: destination)
            if let version = try? await ProcessRunner.run(engine.wineBinary, arguments: ["--version"]),
               version.succeeded, !version.stdout.isEmpty {
                manifest.wineVersion = version.stdout
                engine.manifest = try JSONFile.write(manifest, to: destination.appending(path: Engine.manifestName))
            }
            // Lets macOS give Windows games Game Mode; a failure only costs that.
            _ = try? await GameBundle.build(for: engine)
            return engine
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    private func stagingDirectory() -> URL {
        paths.engines.appending(path: ".staging-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func expectedChecksum(for source: EngineSource) async throws -> String? {
        if let pinned = source.pinnedSHA256 { return pinned }
        guard let url = source.checksumURL else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
        return Checksum.parseShasumFile(String(decoding: data, as: UTF8.self))
    }

    /// Finds the folder that holds `bin/wine64` or `bin/wine`, looking a few levels
    /// deep because every project nests its archive differently.
    static func locateWineRoot(in directory: URL, maxDepth: Int = 5) -> URL? {
        let manager = FileManager.default
        var level = [directory]
        for _ in 0...maxDepth {
            var next: [URL] = []
            for candidate in level {
                let bin = candidate.appending(path: "bin", directoryHint: .isDirectory)
                let hasWine = ["wine64", "wine"].contains {
                    manager.isExecutableFile(atPath: bin.appending(path: $0).path)
                }
                if hasWine { return candidate }
                let children = (try? manager.contentsOfDirectory(
                    at: candidate, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
                )) ?? []
                next += children.filter {
                    (try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]))
                        .map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
                }
            }
            if next.isEmpty { break }
            level = next
        }
        return nil
    }

    /// Reads the version record that winecx-gptk archives ship (`WhiskyWineVersion.plist`).
    static func bundledComponents(in directory: URL) -> [String: String] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [:] }
        var found: URL?
        for case let url as URL in enumerator {
            if enumerator.level > 3 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "WhiskyWineVersion.plist" { found = url; break }
        }
        guard let found,
              let data = try? Data(contentsOf: found),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }

        var components: [String: String] = [:]
        if let dxvk = plist["dxvkVersion"] as? String { components["dxvk"] = dxvk }
        if let dxmt = plist["dxmtVersion"] as? String { components["dxmt"] = dxmt }
        if let version = plist["version"] as? [String: Any],
           let major = version["major"] as? Int, let minor = version["minor"] as? Int, let patch = version["patch"] as? Int {
            components["runtime"] = "\(major).\(minor).\(patch)"
        }
        return components
    }
}
