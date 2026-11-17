import Foundation

/// Installs Apple's Game Porting Toolkit (D3DMetal) into an engine.
///
/// Apple does not allow the toolkit to be redistributed, so Ko'prik never
/// downloads it. The user gets it from developer.apple.com and points
/// Ko'prik at the disk image or folder.
///
/// Layout, as documented in the engine's `lib/external/README`:
/// - `D3DMetal.framework` and `libd3dshared.dylib` go to `lib/external/` as copies.
/// - `lib/wine/x86_64-unix/{d3d10,d3d11,d3d12,dxgi}.so` are symbolic links to
///   `../../external/libd3dshared.dylib`. They must be links, not copies: the
///   library finds the framework relative to its own real location.
/// - The toolkit's Windows DLLs replace Wine's builtin Direct3D DLLs in
///   `lib/wine/x86_64-windows/`. The originals are kept so the import can be undone.
public enum GPTKImporter {
    static let unixBridges = ["d3d10.so", "d3d11.so", "d3d12.so", "dxgi.so"]
    static let backupFolderName = "wine-originals"

    /// Finds the toolkit's `lib` folder inside a mounted volume or a folder the user chose.
    public static func locatePayload(in root: URL) -> URL? {
        let manager = FileManager.default
        func isPayload(_ lib: URL) -> Bool {
            manager.fileExists(atPath: lib.appending(path: "external/libd3dshared.dylib").path)
                && manager.fileExists(atPath: lib.appending(path: "external/D3DMetal.framework").path)
        }
        let direct = [root, root.appending(path: "lib"), root.appending(path: "redist/lib")]
        if let found = direct.first(where: isPayload) { return found }

        guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in enumerator {
            if enumerator.level > 5 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "lib", isPayload(url) { return url }
        }
        return nil
    }

    /// Imports from a `.dmg` or a folder. Returns the toolkit version when it can be read.
    @discardableResult
    public static func importToolkit(from source: URL, into engine: Engine) async throws -> String? {
        guard engine.manifest.d3dmetalCapable else {
            throw KoprikError.invalidArgument("D3DMetal only works on a Wine build with CrossOver's patches. \(engine.name) is not one.")
        }
        if source.pathExtension.lowercased() == "dmg" {
            let mountPoint = FileManager.default.temporaryDirectory.appending(path: "koprik-gptk-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            try await ProcessRunner.runChecked(
                URL(fileURLWithPath: "/usr/bin/hdiutil"),
                arguments: ["attach", source.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path]
            )
            do {
                let version = try await install(fromFolder: mountPoint, into: engine)
                _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", mountPoint.path, "-force"])
                return version
            } catch {
                _ = try? await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: ["detach", mountPoint.path, "-force"])
                throw error
            }
        }
        return try await install(fromFolder: source, into: engine)
    }

    private static func install(fromFolder folder: URL, into engine: Engine) async throws -> String? {
        guard let payload = locatePayload(in: folder) else {
            throw KoprikError.invalidArgument("No Game Porting Toolkit found in \(folder.lastPathComponent). It should contain lib/external/D3DMetal.framework.")
        }
        // Only Apple's own binaries are accepted here: they are loaded into every game.
        for binary in ["external/libd3dshared.dylib", "external/D3DMetal.framework"] {
            let check = try await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/bin/codesign"),
                arguments: ["--verify", "--deep", "-R=anchor apple", payload.appending(path: binary).path]
            )
            guard check.succeeded else {
                throw KoprikError.invalidArgument("\(binary) is not signed by Apple, so it was not imported.")
            }
        }

        let manager = FileManager.default
        let lib = engine.wineRoot.appending(path: "lib", directoryHint: .isDirectory)
        let external = lib.appending(path: "external", directoryHint: .isDirectory)
        let windows = lib.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory)
        let unix = lib.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
        let backups = engine.directory.appending(path: backupFolderName, directoryHint: .isDirectory)
        try manager.createDirectory(at: external, withIntermediateDirectories: true)
        try manager.createDirectory(at: backups, withIntermediateDirectories: true)

        for name in ["libd3dshared.dylib", "D3DMetal.framework"] {
            let destination = external.appending(path: name)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.copyItem(at: payload.appending(path: "external/\(name)"), to: destination)
        }

        let payloadWindows = payload.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory)
        for dll in (try? manager.contentsOfDirectory(at: payloadWindows, includingPropertiesForKeys: nil)) ?? []
        where dll.pathExtension.lowercased() == "dll" {
            let destination = windows.appending(path: dll.lastPathComponent)
            let backup = backups.appending(path: dll.lastPathComponent)
            if manager.fileExists(atPath: destination.path) {
                // Keep the very first original; a re-import must not overwrite it with Apple's file.
                if !manager.fileExists(atPath: backup.path) { try manager.copyItem(at: destination, to: backup) }
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: dll, to: destination)
        }

        for bridge in unixBridges {
            let link = unix.appending(path: bridge)
            if (try? link.checkResourceIsReachable()) == true || (try? manager.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try manager.removeItem(at: link)
            }
            try manager.createSymbolicLink(atPath: link.path, withDestinationPath: "../../external/libd3dshared.dylib")
        }
        await Archive.removeQuarantine(at: external)
        // The bundle holds a copy of the unix directory, which just changed.
        _ = try? await GameBundle.build(for: engine)
        return version(in: engine)
    }

    /// Undoes an import, putting Wine's own Direct3D DLLs back.
    public static func remove(from engine: Engine) async throws {
        let manager = FileManager.default
        let lib = engine.wineRoot.appending(path: "lib", directoryHint: .isDirectory)
        let windows = lib.appending(path: "wine/x86_64-windows", directoryHint: .isDirectory)
        let backups = engine.directory.appending(path: backupFolderName, directoryHint: .isDirectory)

        for backup in (try? manager.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)) ?? [] {
            let destination = windows.appending(path: backup.lastPathComponent)
            if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
            try manager.moveItem(at: backup, to: destination)
        }
        for bridge in unixBridges {
            try? manager.removeItem(at: lib.appending(path: "wine/x86_64-unix/\(bridge)"))
        }
        for name in ["libd3dshared.dylib", "D3DMetal.framework"] {
            try? manager.removeItem(at: lib.appending(path: "external/\(name)"))
        }
        _ = try? await GameBundle.build(for: engine)
    }

    /// The imported toolkit's version, from the framework's `Info.plist`.
    public static func version(in engine: Engine) -> String? {
        let framework = engine.wineRoot.appending(path: "lib/external/D3DMetal.framework")
        let candidates = ["Resources/Info.plist", "Versions/A/Resources/Info.plist"]
        for candidate in candidates {
            guard let data = try? Data(contentsOf: framework.appending(path: candidate)),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let version = plist["CFBundleShortVersionString"] as? String else { continue }
            return version
        }
        return nil
    }
}
