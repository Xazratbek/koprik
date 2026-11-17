import CoreServices
import Foundation

/// Lets links that Windows programs registered (`notion://`, `zoommtg://`,
/// `steam://`, ...) reach them from the Mac.
///
/// Sign-in flows depend on this: Notion's "Continue in Browser" signs in on
/// the web, which then opens `notion://...` to hand the session back. macOS
/// knows nothing about schemes registered inside a Wine prefix, so the link
/// would go nowhere. For each bottle Ko'prik builds a small helper app that
/// declares those schemes and forwards every link to Ko'prik
/// (`koprik://open-url/<bottle>/<link>`), which runs `start <link>` in the
/// bottle; Wine then finds the program through the Windows registry.
public enum LinkBridge {
    /// Schemes Ko'prik never takes from macOS, even when a Windows program registers them.
    static let reserved: Set<String> = ["http", "https", "file", "mailto", "ftp", "koprik", "about", "data", "javascript"]

    /// URL schemes the bottle's programs registered, read from the registry
    /// files (`HKCU\Software\Classes` and `HKLM\Software\Classes`).
    public static func schemes(in bottle: Bottle) -> [String] {
        var found: Set<String> = []
        for file in ["user.reg", "system.reg"] {
            guard let text = try? String(contentsOf: bottle.prefix.appending(path: file), encoding: .utf8) else { continue }
            found.formUnion(schemes(inRegistry: text))
        }
        return found.subtracting(reserved).sorted()
    }

    static func schemes(inRegistry text: String) -> Set<String> {
        var result: Set<String> = []
        var current: String?
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("[") {
                // [Software\\Classes\\notion] 1794922810
                let key = line.dropFirst().prefix { $0 != "]" }
                let parts = key.components(separatedBy: "\\\\")
                if parts.count == 3, parts[0].caseInsensitiveCompare("Software") == .orderedSame,
                   parts[1].caseInsensitiveCompare("Classes") == .orderedSame {
                    current = parts[2]
                } else {
                    current = nil
                }
            } else if let scheme = current, line.hasPrefix("\"URL Protocol\"") {
                let lowered = scheme.lowercased()
                // RFC 3986: a letter, then letters, digits, "+", "-" or ".".
                if let first = lowered.first, first.isLetter,
                   lowered.allSatisfy({ $0.isLetter || $0.isNumber || "+-.".contains($0) }) {
                    result.insert(lowered)
                }
            }
        }
        return result
    }

    /// The program and arguments a scheme's handler runs, from
    /// `Software\Classes\<scheme>\shell\open\command`, with `%1` filled in.
    /// Wine's `start` only looks in HKLM's classes, so links registered per user
    /// (Notion, Zoom) are resolved here instead.
    public static func handlerCommand(for link: String, in bottle: Bottle) -> (program: String, arguments: [String])? {
        guard let colon = link.firstIndex(of: ":") else { return nil }
        let scheme = link[..<colon].lowercased()
        for file in ["user.reg", "system.reg"] {
            guard let text = try? String(contentsOf: bottle.prefix.appending(path: file), encoding: .utf8),
                  let command = command(for: scheme, inRegistry: text) else { continue }
            let parts = ProgramStore.splitArguments(command)
            guard let program = parts.first else { continue }
            var arguments = Array(parts.dropFirst()).map { $0.replacingOccurrences(of: "%1", with: link) }
            if !command.contains("%1") { arguments.append(link) }
            return (program, arguments)
        }
        return nil
    }

    static func command(for scheme: String, inRegistry text: String) -> String? {
        var inKey = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("[") {
                let key = line.dropFirst().prefix { $0 != "]" }.lowercased()
                inKey = key == "software\\\\classes\\\\\(scheme)\\\\shell\\\\open\\\\command"
            } else if inKey, line.hasPrefix("@=\"") {
                var value = String(line.dropFirst(3))
                if value.hasSuffix("\"") { value.removeLast() }
                return value.replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\\\", with: "\\")
            }
        }
        return nil
    }

    public static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications/Koprik/Links", directoryHint: .isDirectory)
    }

    static func handlerURL(for bottle: Bottle) -> URL {
        let safe = bottle.name.map { $0.isLetter || $0.isNumber || $0 == " " || $0 == "-" ? $0 : "-" }
        return folder.appending(path: "\(String(safe)) Links.app", directoryHint: .isDirectory)
    }

    /// Builds or refreshes the bottle's link helper. Returns the schemes it
    /// now handles; does nothing when they have not changed.
    @discardableResult
    public static func update(for bottle: Bottle) async throws -> [String] {
        let schemes = schemes(in: bottle)
        let app = handlerURL(for: bottle)
        let marker = bottle.directory.appending(path: ".link-schemes")
        let signature = schemes.joined(separator: ",")
        let manager = FileManager.default
        if (try? String(contentsOf: marker, encoding: .utf8)) == signature, manager.fileExists(atPath: app.path) {
            return schemes
        }
        if schemes.isEmpty {
            try? manager.removeItem(at: app)
            try? manager.removeItem(at: marker)
            return []
        }
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        if manager.fileExists(atPath: app.path) { try manager.removeItem(at: app) }

        // An AppleScript applet is the smallest app that can receive a URL from macOS.
        let prefix = "koprik://open-url/\(bottle.id.uuidString)/"
        try await ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/osacompile"), arguments: [
            "-o", app.path,
            "-e", "on open location theURL",
            "-e", "tell application id \"uz.koprik.app\" to open location (\"\(prefix)\" & theURL)",
            "-e", "end open location",
        ])

        let plistURL = app.appending(path: "Contents/Info.plist")
        let data = try Data(contentsOf: plistURL)
        guard var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw KoprikError.invalidArgument("The link helper's Info.plist could not be read.")
        }
        let identifier = "uz.koprik.links." + bottle.id.uuidString.lowercased()
        info["CFBundleIdentifier"] = identifier
        info["CFBundleName"] = "\(bottle.name) Links"
        info["LSUIElement"] = true
        info["LSBackgroundOnly"] = true
        info["CFBundleURLTypes"] = [[
            "CFBundleURLName": "Windows programs in \(bottle.name)",
            "CFBundleURLSchemes": schemes,
        ]]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plistURL)
        try await ProcessRunner.runChecked(URL(fileURLWithPath: "/usr/bin/codesign"), arguments: ["--force", "--deep", "--sign", "-", app.path])
        _ = try? await ProcessRunner.run(lsregister, arguments: ["-f", app.path])

        // Claim the schemes, unless a native Mac app already handles one (Zoom for Mac, say).
        for scheme in schemes where LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() == nil
            || (LSCopyDefaultHandlerForURLScheme(scheme as CFString)?.takeRetainedValue() as String?)?.hasPrefix("uz.koprik.links.") == true {
            LSSetDefaultHandlerForURLScheme(scheme as CFString, identifier as CFString)
        }
        try signature.write(to: marker, atomically: true, encoding: .utf8)
        return schemes
    }

    public static func remove(for bottle: Bottle) async {
        let app = handlerURL(for: bottle)
        _ = try? await ProcessRunner.run(lsregister, arguments: ["-u", app.path])
        try? FileManager.default.removeItem(at: app)
        try? FileManager.default.removeItem(at: bottle.directory.appending(path: ".link-schemes"))
    }

    /// Splits `koprik://open-url/<bottle>/<link>` back into its parts. The
    /// link is taken verbatim from the text, because URL parsing would fold
    /// its own `//`.
    public static func parseForwarded(_ url: URL) -> (bottleID: UUID, link: String)? {
        let text = url.absoluteString
        let prefix = "koprik://open-url/"
        guard text.lowercased().hasPrefix(prefix) else { return nil }
        let rest = text.dropFirst(prefix.count)
        guard let slash = rest.firstIndex(of: "/"), let id = UUID(uuidString: String(rest[..<slash])) else { return nil }
        let link = String(rest[rest.index(after: slash)...])
        guard let colon = link.firstIndex(of: ":"), !reserved.contains(link[..<colon].lowercased()) else { return nil }
        return (id, link)
    }

    private static let lsregister = URL(fileURLWithPath:
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
}
