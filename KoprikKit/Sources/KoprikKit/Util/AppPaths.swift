import Foundation

/// Where Ko'prik keeps everything it owns on disk.
///
/// The root defaults to `~/Library/Application Support/Koprik`. Setting the
/// `KOPRIK_HOME` environment variable moves it, which the tests and the CLI use
/// to work against a scratch directory.
public struct AppPaths: Sendable, Equatable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    public static var `default`: AppPaths {
        if let override = ProcessInfo.processInfo.environment["KOPRIK_HOME"], !override.isEmpty {
            return AppPaths(root: URL(fileURLWithPath: override, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(root: support.appending(path: "Koprik", directoryHint: .isDirectory))
    }

    public var engines: URL { root.appending(path: "Engines", directoryHint: .isDirectory) }
    public var components: URL { root.appending(path: "Components", directoryHint: .isDirectory) }
    public var bottles: URL { root.appending(path: "Bottles", directoryHint: .isDirectory) }
    public var templates: URL { root.appending(path: "Templates", directoryHint: .isDirectory) }
    public var cache: URL { root.appending(path: "Cache", directoryHint: .isDirectory) }
    public var downloads: URL { cache.appending(path: "downloads", directoryHint: .isDirectory) }
    public var installers: URL { cache.appending(path: "installers", directoryHint: .isDirectory) }

    /// Creates every top-level directory. Safe to call repeatedly.
    public func ensureDirectories() throws {
        let manager = FileManager.default
        for directory in [engines, components, bottles, templates, downloads, installers] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
