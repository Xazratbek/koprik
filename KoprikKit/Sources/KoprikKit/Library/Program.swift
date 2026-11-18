import CryptoKit
import Foundation

/// Something the user can launch from a bottle: an executable, or a game that
/// the Windows Steam client installed.
public struct Program: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case executable
        case steam
        /// Installed with legendary; started with Epic's sign-in arguments.
        case epic
        /// Installed with gogdl; started from its goggame-<id>.info.
        case gog
    }

    /// Stable across scans, so settings and play time stay attached.
    public var id: String
    public var name: String
    public var kind: Kind
    /// For executables: a Windows path inside the bottle (`C:\...`) or an
    /// absolute path on the Mac. For Steam games: the install folder on the Mac.
    public var location: String
    public var steamAppID: Int?
    /// Epic's app name or GOG's product id.
    public var storeID: String?
    public var arguments: [String]
    /// Overrides laid on top of the bottle's settings for this program only.
    public var settings: LaunchSettings
    public var favorite: Bool
    public var hidden: Bool
    /// True when the user added the program by hand rather than a scan finding it.
    public var pinned: Bool
    public var launchCount: Int
    public var playTime: TimeInterval
    public var lastPlayed: Date?

    public init(
        id: String,
        name: String,
        kind: Kind = .executable,
        location: String,
        steamAppID: Int? = nil,
        storeID: String? = nil,
        arguments: [String] = [],
        settings: LaunchSettings = LaunchSettings(),
        favorite: Bool = false,
        hidden: Bool = false,
        pinned: Bool = false,
        launchCount: Int = 0,
        playTime: TimeInterval = 0,
        lastPlayed: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.location = location
        self.steamAppID = steamAppID
        self.storeID = storeID
        self.arguments = arguments
        self.settings = settings
        self.favorite = favorite
        self.hidden = hidden
        self.pinned = pinned
        self.launchCount = launchCount
        self.playTime = playTime
        self.lastPlayed = lastPlayed
    }

    /// Whether anything about the program differs from what a scan would produce,
    /// which is what decides whether it needs a file of its own.
    var hasUserState: Bool {
        favorite || hidden || pinned || launchCount > 0 || !arguments.isEmpty || settings != LaunchSettings()
    }

    /// The executable on the Mac's file system, when the program is one.
    public func executableURL(in bottle: Bottle) -> URL? {
        guard kind == .executable else { return nil }
        if location.hasPrefix("/") { return URL(fileURLWithPath: location) }
        return WindowsPath.hostURL(for: location, prefix: bottle.prefix)
    }

    public static func identifier(forExecutableAt location: String) -> String {
        let digest = SHA256.hash(data: Data(location.lowercased().utf8))
        return "exe-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public static func identifier(forSteamApp appID: Int) -> String {
        "steam-\(appID)"
    }
}

/// Lists a bottle's programs and stores what the user changed about them.
///
/// Programs are discovered fresh on every listing (Start Menu shortcuts and
/// Steam's manifests), then merged with the records saved under
/// `programs/`. Only programs the user touched get a file.
public actor ProgramStore {
    public init() {}

    public func programs(in bottle: Bottle, includeHidden: Bool = false) -> [Program] {
        var byID: [String: Program] = [:]
        for program in Self.discover(in: bottle) { byID[program.id] = program }

        for saved in savedPrograms(in: bottle) {
            if var found = byID[saved.id] {
                // Keep the user's state, refresh what the scan knows better.
                found.arguments = saved.arguments.isEmpty ? found.arguments : saved.arguments
                found.settings = saved.settings
                found.favorite = saved.favorite
                found.hidden = saved.hidden
                found.pinned = saved.pinned
                found.launchCount = saved.launchCount
                found.playTime = saved.playTime
                found.lastPlayed = saved.lastPlayed
                found.name = saved.pinned ? saved.name : found.name
                byID[saved.id] = found
            } else if saved.pinned || Self.stillExists(saved, in: bottle) {
                byID[saved.id] = saved
            }
        }
        return byID.values
            .filter { includeHidden || !$0.hidden }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func program(id: String, in bottle: Bottle) -> Program? {
        programs(in: bottle, includeHidden: true).first { $0.id == id }
    }

    /// Stores a program's record, or removes the file when nothing user-made is left in it.
    @discardableResult
    public func save(_ program: Program, in bottle: Bottle) throws -> Program {
        let file = Self.file(for: program.id, in: bottle)
        guard program.hasUserState else {
            try? FileManager.default.removeItem(at: file)
            return program
        }
        try FileManager.default.createDirectory(at: bottle.programs, withIntermediateDirectories: true)
        return try JSONFile.write(program, to: file)
    }

    /// Adds an executable the scans would not find by themselves.
    @discardableResult
    public func pin(executable: URL, name: String? = nil, in bottle: Bottle) throws -> Program {
        let location = WindowsPath.windowsPath(for: executable, prefix: bottle.prefix) ?? executable.path
        let id = Program.identifier(forExecutableAt: location)
        var program = program(id: id, in: bottle) ?? Program(
            id: id,
            name: name ?? executable.deletingPathExtension().lastPathComponent,
            location: location
        )
        program.pinned = true
        program.hidden = false
        if let name { program.name = name }
        return try save(program, in: bottle)
    }

    public func remove(_ program: Program, in bottle: Bottle) {
        try? FileManager.default.removeItem(at: Self.file(for: program.id, in: bottle))
    }

    /// Adds one finished session to the program's statistics.
    @discardableResult
    public func recordSession(programID: String, in bottle: Bottle, started: Date, duration: TimeInterval) throws -> Program? {
        guard var program = program(id: programID, in: bottle) else { return nil }
        program.launchCount += 1
        program.playTime += max(0, duration)
        program.lastPlayed = started
        return try save(program, in: bottle)
    }

    // MARK: Discovery

    private func savedPrograms(in bottle: Bottle) -> [Program] {
        let files = (try? FileManager.default.contentsOfDirectory(at: bottle.programs, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONFile.read(Program.self, from: $0) }
    }

    private static func file(for id: String, in bottle: Bottle) -> URL {
        bottle.programs.appending(path: "\(id).json")
    }

    private static func stillExists(_ program: Program, in bottle: Bottle) -> Bool {
        switch program.kind {
        case .steam, .epic, .gog:
            FileManager.default.fileExists(atPath: program.location)
        case .executable:
            program.executableURL(in: bottle).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        }
    }

    /// Names that mark a shortcut as something other than the program itself.
    private static let noiseWords = [
        "uninstall", "unins", "readme", "read me", "license", "licence", "help", "manual",
        "website", "web site", "homepage", "documentation", "release notes", "changelog", "support",
    ]

    static func discover(in bottle: Bottle) -> [Program] {
        var found: [String: Program] = [:]

        for shortcut in startMenuShortcuts(in: bottle) {
            guard let link = ShellLink(url: shortcut), let target = link.targetPath else { continue }
            let name = displayName(fromShortcut: shortcut.deletingPathExtension().lastPathComponent)
            let lowered = name.lowercased()
            guard target.lowercased().hasSuffix(".exe"),
                  !noiseWords.contains(where: lowered.contains),
                  !target.lowercased().contains("\\windows\\"),
                  let host = WindowsPath.hostURL(for: target, prefix: bottle.prefix),
                  FileManager.default.fileExists(atPath: host.path) else { continue }

            let id = Program.identifier(forExecutableAt: target)
            // Several shortcuts to one program (Start Menu, Desktop): keep the plainest name.
            if let existing = found[id] {
                if name.count < existing.name.count { found[id]?.name = name }
                continue
            }
            let arguments = link.arguments.map(splitArguments) ?? []
            found[id] = Program(id: id, name: name, location: target, arguments: arguments)
        }

        // Epic games legendary installed into this bottle.
        let epicRecord = AppPaths.default.root.appending(path: "Stores/legendary/installed.json")
        if let data = try? Data(contentsOf: epicRecord),
           let installed = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            let prefix = bottle.prefix.standardizedFileURL.path
            for (appName, entry) in installed {
                guard let path = entry["install_path"] as? String, URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(prefix) else { continue }
                let id = "epic-\(appName)"
                found[id] = Program(id: id, name: entry["title"] as? String ?? appName, kind: .epic, location: path, storeID: appName)
            }
        }
        for (gogID, folder) in GOGStore.installedGames(in: [bottle]) {
            let id = "gog-\(gogID)"
            found[id] = Program(id: id, name: folder.lastPathComponent, kind: .gog, location: folder.path, storeID: gogID)
        }

        for app in SteamLibrary.apps(in: bottle) {
            let id = Program.identifier(forSteamApp: app.appID)
            found[id] = Program(id: id, name: app.name, kind: .steam, location: app.installDirectory.path, steamAppID: app.appID)
        }
        return Array(found.values)
    }

    private static func startMenuShortcuts(in bottle: Bottle) -> [URL] {
        let manager = FileManager.default
        var roots = [bottle.driveC.appending(path: "ProgramData/Microsoft/Windows/Start Menu", directoryHint: .isDirectory)]
        let users = bottle.driveC.appending(path: "users", directoryHint: .isDirectory)
        for user in (try? manager.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [] {
            roots.append(user.appending(path: "AppData/Roaming/Microsoft/Windows/Start Menu", directoryHint: .isDirectory))
            roots.append(user.appending(path: "Desktop", directoryHint: .isDirectory))
        }
        roots.append(bottle.driveC.appending(path: "users/Public/Desktop", directoryHint: .isDirectory))

        var shortcuts: [URL] = []
        for root in roots {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "lnk" {
                shortcuts.append(url)
            }
        }
        return shortcuts
    }

    /// A shortcut name without the verb installers put in front of it:
    /// "Start game Need for Speed" becomes "Need for Speed".
    static func displayName(fromShortcut name: String) -> String {
        let verbs = ["start game ", "play game ", "launch game ", "run game ", "start ", "play ", "launch ",
                     "запустить игру ", "запуск игры ", "играть в "]
        let lowered = name.lowercased()
        for verb in verbs where lowered.hasPrefix(verb) && name.count > verb.count + 2 {
            return String(name.dropFirst(verb.count))
        }
        return name
    }

    /// Splits a Windows command line into arguments, honouring double quotes.
    static func splitArguments(_ line: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character.isWhitespace && !quoted {
                if !current.isEmpty { arguments.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { arguments.append(current) }
        return arguments
    }
}
