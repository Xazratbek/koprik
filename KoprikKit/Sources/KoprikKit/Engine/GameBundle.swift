import Foundation

/// Wraps an engine's Wine loader in an app bundle so that macOS treats every
/// Windows program as a game: Game Mode turns on in full screen (more CPU and
/// GPU priority, half the Bluetooth input latency), and the Dock shows one
/// recognisable app instead of "wine".
///
/// macOS only grants Game Mode to a process Launch Services knows by a bundle
/// that sets `LSSupportsGameMode` (an Info.plist embedded in a bare executable
/// is not enough, and a symbolic link is resolved back to the bare file).
/// The bundle is built so Wine's own path logic still works from inside it:
///
/// - Wine's unix loader looks for `ntdll.so` beside its real path, and ntdll
///   starts every child process from `<its directory>/wine`. So
///   `Contents/MacOS` holds the whole `x86_64-unix` directory as APFS clones
///   (no extra disk space), and the game itself also runs from the bundle.
/// - ntdll finds the other directories relative to its own location:
///   `Contents/MacOS/x86_64-unix` points back to `.`, and the Windows DLL
///   directories are links to the engine's.
/// - The unix libraries load their dependencies from `@loader_path/../../`,
///   which inside the bundle is the bundle root, so the root links to every
///   item of the engine's `lib` folder.
///
/// Measured with Brawlhalla on an M2 Pro: the Metal HUD reports "Game Mode
/// On", where the bare loader stays "Off" (docs/SINOV.md).
public enum GameBundle {
    public static let name = "Koprik Game.app"
    public static let identifier = "uz.koprik.game"

    static func url(for engine: Engine) -> URL {
        engine.wineRoot.appending(path: name, directoryHint: .isDirectory)
    }

    /// The loader inside the bundle, when the bundle exists and is current.
    public static func loader(for engine: Engine) -> URL? {
        let loader = url(for: engine).appending(path: "Contents/MacOS/wine")
        return FileManager.default.isExecutableFile(atPath: loader.path) ? loader : nil
    }

    /// Builds (or rebuilds) the bundle. Safe to call repeatedly; it is quick.
    /// Must be rebuilt whenever the engine's unix directory changes, such as
    /// after importing or removing the Game Porting Toolkit.
    @discardableResult
    public static func build(for engine: Engine) async throws -> URL {
        let manager = FileManager.default
        let lib = engine.wineRoot.appending(path: "lib", directoryHint: .isDirectory)
        let unix = lib.appending(path: "wine/x86_64-unix", directoryHint: .isDirectory)
        guard manager.fileExists(atPath: unix.appending(path: "ntdll.so").path) else {
            throw KoprikError.wineBinaryNotFound(engine.wineRoot)
        }

        let bundle = url(for: engine)
        let staging = engine.wineRoot.appending(path: ".\(name)-\(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = staging.appending(path: "Contents", directoryHint: .isDirectory)
        let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        do {
            try manager.createDirectory(at: contents, withIntermediateDirectories: true)
            // copyItem clones on APFS, so this costs no space; symbolic links inside are kept as links.
            try manager.copyItem(at: unix, to: macOS)
            try manager.createSymbolicLink(atPath: macOS.appending(path: "x86_64-unix").path, withDestinationPath: ".")
            for windows in ["x86_64-windows", "i386-windows"] {
                try manager.createSymbolicLink(
                    atPath: macOS.appending(path: windows).path,
                    withDestinationPath: "../../../lib/wine/\(windows)"
                )
            }
            for item in try manager.contentsOfDirectory(atPath: lib.path) where item != "wine" {
                try manager.createSymbolicLink(atPath: staging.appending(path: item).path, withDestinationPath: "../lib/\(item)")
            }
            try manager.createSymbolicLink(atPath: staging.appending(path: "share").path, withDestinationPath: "../share")
            try infoPlist(version: engine.manifest.wineVersion ?? "1.0").write(to: contents.appending(path: "Info.plist"))
            // Ko'prik's icon for Windows programs in the Dock, when Ko'prik is installed.
            let icon = URL(fileURLWithPath: "/Applications/Koprik.app/Contents/Resources/AppIcon.icns")
            if manager.fileExists(atPath: icon.path) {
                let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
                try manager.createDirectory(at: resources, withIntermediateDirectories: true)
                try manager.copyItem(at: icon, to: resources.appending(path: "AppIcon.icns"))
            }

            // The cloned loader keeps its original ad hoc signature, which is
            // valid for its unchanged contents. Re-signing in place fails
            // ("unsealed contents present in the bundle root") and is not needed.

            if manager.fileExists(atPath: bundle.path) { try manager.removeItem(at: bundle) }
            try manager.moveItem(at: staging, to: bundle)
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
        _ = try? await ProcessRunner.run(lsregister, arguments: ["-f", bundle.path])
        return bundle
    }

    public static func remove(from engine: Engine) async {
        let bundle = url(for: engine)
        _ = try? await ProcessRunner.run(lsregister, arguments: ["-u", bundle.path])
        try? FileManager.default.removeItem(at: bundle)
    }

    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")

    static func infoPlist(version: String) throws -> Data {
        let info: [String: Any] = [
            "CFBundleExecutable": "wine",
            "CFBundleIdentifier": identifier,
            "CFBundleName": "Ko'prik Game",
            "CFBundleDisplayName": "Ko'prik Game",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version.replacingOccurrences(of: "wine-", with: ""),
            "CFBundleVersion": "1",
            "CFBundleInfoDictionaryVersion": "6.0",
            // Wine's mac driver subclasses NSApplication under this name.
            "NSPrincipalClass": "WineApplication",
            // Without this every background Wine process (services.exe,
            // winedevice.exe, explorer.exe ...) appears in the Dock as a blank
            // app. Wine's Mac driver turns a process into a regular app only
            // when it shows a window, as CrossOver's own loader plist does.
            "LSUIElement": true,
            "CFBundleIconFile": "AppIcon",
            "LSApplicationCategoryType": "public.app-category.games",
            "LSSupportsGameMode": true,
            "NSHighResolutionCapable": true,
            "GCSupportsControllerUserInteraction": true,
        ]
        return try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
    }
}
