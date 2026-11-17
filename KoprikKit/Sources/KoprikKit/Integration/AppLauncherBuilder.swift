import Foundation

/// Creates small `.app` bundles that start a Windows program, so it can sit
/// in the Dock, in Launchpad and in Spotlight like any Mac app.
///
/// The bundle holds no Wine logic of its own: it opens a `koprik://` link,
/// and Ko'prik does the launching. That way a launcher never goes stale when
/// settings or the engine change.
public enum AppLauncherBuilder {
    public static var defaultFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Koprik", directoryHint: .isDirectory)
    }

    /// The link a launcher opens, also usable from scripts and Shortcuts.
    public static func launchURL(bottleID: UUID, programID: String) -> URL {
        URL(string: "koprik://run/\(bottleID.uuidString)/\(programID)")!
    }

    /// Parses a `koprik://run/<bottle>/<program>` link.
    public static func parse(_ url: URL) -> (bottleID: UUID, programID: String)? {
        guard url.scheme?.lowercased() == "koprik", url.host()?.lowercased() == "run" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2, let bottleID = UUID(uuidString: parts[0]) else { return nil }
        return (bottleID, parts[1])
    }

    /// Writes the bundle and returns its location. An existing launcher with
    /// the same name is replaced.
    @discardableResult
    public static func create(
        for program: Program,
        in bottle: Bottle,
        iconICNS: Data? = nil,
        folder: URL = defaultFolder
    ) throws -> URL {
        let manager = FileManager.default
        let safeName = program.name.map { "/:\\".contains($0) ? "-" : $0 }
        let bundle = folder.appending(path: "\(String(safeName)).app", directoryHint: .isDirectory)
        if manager.fileExists(atPath: bundle.path) { try manager.removeItem(at: bundle) }

        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        let macOS = contents.appending(path: "MacOS", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        try manager.createDirectory(at: macOS, withIntermediateDirectories: true)
        try manager.createDirectory(at: resources, withIntermediateDirectories: true)

        let link = launchURL(bottleID: bottle.id, programID: program.id).absoluteString
        let script = "#!/bin/sh\nexec /usr/bin/open \"\(link)\"\n"
        let executable = macOS.appending(path: "launch")
        try Data(script.utf8).write(to: executable)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        var info: [String: Any] = [
            "CFBundleName": program.name,
            "CFBundleDisplayName": program.name,
            "CFBundleIdentifier": "uz.koprik.launcher.\(program.id)",
            "CFBundleExecutable": "launch",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSUIElement": true,
            "LSApplicationCategoryType": program.kind == .steam ? "public.app-category.games" : "public.app-category.utilities",
        ]
        if let iconICNS {
            try iconICNS.write(to: resources.appending(path: "icon.icns"))
            info["CFBundleIconFile"] = "icon"
        }
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }
}
