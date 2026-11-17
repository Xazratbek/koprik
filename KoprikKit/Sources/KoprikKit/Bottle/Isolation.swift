import Foundation

/// How far a bottle is walled off from the Mac.
///
/// Wine is not a sandbox: a Windows program sees the whole Mac disk as drive
/// Z: and runs with the user's own rights. Tested: a plain `cmd /c echo ... >
/// Z:\Users\<you>\Desktop\file` writes to the Mac desktop. Isolation closes
/// that with the kernel's sandbox (Seatbelt, through `sandbox-exec`), which
/// every Wine process of the bottle inherits, and nothing a Windows program
/// does can lift.
public enum Isolation: String, Codable, Sendable, CaseIterable {
    /// Full access, like CrossOver. For trusted software such as Steam.
    case off
    /// No access to your files, and no Mac programs can be started. Internet works.
    case files
    /// As `files`, and no internet either.
    case full

    public var isOn: Bool { self != .off }
}

/// Builds the sandbox profile for an isolated bottle.
public enum Sandbox {
    /// The path with every symbolic link resolved, as the kernel sees it.
    /// Foundation's resolvingSymlinksInPath drops /private, which Seatbelt needs.
    static func realPath(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static let executable = URL(fileURLWithPath: "/usr/bin/sandbox-exec")

    public static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
    }

    /// Folders in the home directory the bottle may read: the bottle, the
    /// engine, and the parts of Library that macOS frameworks need to draw
    /// windows (fonts, preferences, caches). Everything else in the home
    /// directory (Documents, Desktop, Downloads, Pictures, Mail, Messages,
    /// Keychains, browser profiles, ssh keys, other apps' data) is denied.
    static func readableHomePaths(bottle: Bottle, engine: Engine, home: URL) -> [String] {
        [
            bottle.directory.path,
            engine.directory.path,
            home.appending(path: "Library/Fonts").path,
            home.appending(path: "Library/Preferences").path,
            home.appending(path: "Library/Caches").path,
            home.appending(path: "Library/Keyboard Layouts").path,
            home.appending(path: "Library/Input Methods").path,
            home.appending(path: "Library/Application Support/Koprik/Components").path,
        ]
    }

    /// A Seatbelt profile for `sandbox-exec -p`.
    ///
    /// Starts from "allow" so that Metal, AppKit, audio and input keep
    /// working, then removes what a hostile program could abuse: reading
    /// and writing the user's files, starting any program that is not part
    /// of the engine, and, at `full`, the network. Writes are allowed only
    /// inside the bottle and the temporary folders Wine needs.
    public static func profile(for bottle: Bottle, engine: Engine, isolation: Isolation,
                               home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        // Seatbelt compares real paths (/private/var/..., not /var/...), so every path is resolved first.
        func quoted(_ path: String) -> String {
            let path = realPath(path)
            return "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        let homePath = home.standardizedFileURL.path
        let readable = readableHomePaths(bottle: bottle, engine: engine, home: home)
            .map { "(subpath \(quoted($0)))" }.joined(separator: " ")
        let writable = [
            bottle.directory.path,
            home.appending(path: "Library/Caches").path,
        ].map { "(subpath \(quoted($0)))" }.joined(separator: " ")

        var lines = [
            "(version 1)",
            "(allow default)",
            // The home directory: nothing but the allowlist, for reading or writing.
            "(deny file-read* file-write* (subpath \(quoted(homePath))))",
            "(allow file-read* (literal \(quoted(homePath))) \(readable))",
            // Names and sizes (not contents) along the way, which path resolution needs.
            "(allow file-read-metadata)",
            "(allow file-write* \(writable))",
            // Other users' data and system configuration stay off limits.
            "(deny file-write* (subpath \"/Applications\") (subpath \"/Library\") (subpath \"/usr/local\") (subpath \"/opt\") (subpath \"/Volumes\"))",
            "(deny file-read* (subpath \"/Volumes\"))",
            // Only the engine's own binaries may be started: no shell, no `open`, no Mac apps.
            "(deny process-exec*)",
            "(allow process-exec* (subpath \(quoted(engine.directory.path))))",
            // No Apple Events to other apps (they could make Finder or Terminal act on its behalf).
            "(deny appleevent-send)",
        ]
        if isolation == .full {
            lines.append("(deny network-outbound (remote ip))")
            lines.append("(deny network-inbound (local ip))")
        }
        return lines.joined(separator: "\n")
    }
}

extension WineRunner {
    /// A runner for the bottle that wraps every Wine process in the bottle's sandbox when it is isolated.
    public static func forBottle(_ bottle: Bottle, engine: Engine) -> WineRunner {
        let isolation = bottle.config.isolation ?? .off
        guard isolation.isOn, Sandbox.isAvailable else { return WineRunner(engine: engine) }
        return WineRunner(engine: engine, sandboxProfile: Sandbox.profile(for: bottle, engine: engine, isolation: isolation))
    }
}
