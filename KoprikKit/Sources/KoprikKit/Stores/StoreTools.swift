import Foundation

/// A game owned on a store that Ko'prik can install without the store's own launcher.
public struct StoreGame: Codable, Sendable, Equatable, Identifiable {
    public enum Store: String, Codable, Sendable {
        case epic, gog
    }

    public var store: Store
    /// Epic's `app_name`, or GOG's numeric product id.
    public var storeID: String
    public var title: String
    public var installPath: String?
    public var coverURL: URL?

    public var id: String { "\(store.rawValue)-\(storeID)" }
    public var isInstalled: Bool { installPath != nil }

    public init(store: Store, storeID: String, title: String, installPath: String? = nil, coverURL: URL? = nil) {
        self.store = store
        self.storeID = storeID
        self.title = title
        self.installPath = installPath
        self.coverURL = coverURL
    }
}

/// How to start an installed store game.
public struct StoreLaunch: Sendable, Equatable {
    public var executable: URL
    public var workingDirectory: URL
    public var arguments: [String]
}

/// Command-line store clients, downloaded as single self-contained binaries
/// (no Python needed): legendary for Epic, heroic-gogdl for GOG.
public enum StoreTool: String, Sendable, CaseIterable {
    case legendary, gogdl

    public var version: String {
        switch self {
        case .legendary: "0.21.1"
        case .gogdl: "1.4.0"
        }
    }

    var downloadURL: URL {
        switch self {
        case .legendary:
            URL(string: "https://github.com/derrod/legendary/releases/download/\(version)/legendary_macOS_arm64")!
        case .gogdl:
            URL(string: "https://github.com/Heroic-Games-Launcher/heroic-gogdl/releases/download/v\(version)/gogdl_macos_arm64")!
        }
    }

    func binary(in paths: AppPaths) -> URL {
        paths.components.appending(path: "stores/\(rawValue)-\(version)")
    }

    /// Downloads the tool on first use.
    func ensure(in paths: AppPaths) async throws -> URL {
        let binary = binary(in: paths)
        let manager = FileManager.default
        if manager.isExecutableFile(atPath: binary.path) { return binary }
        try manager.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await Downloader.download(downloadURL, to: binary)
        try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binary.path)
        await Archive.removeQuarantine(at: binary)
        return binary
    }

    func run(_ arguments: [String], paths: AppPaths, environment extra: [String: String] = [:]) async throws -> ProcessResult {
        let binary = try await ensure(in: paths)
        var environment = ProcessInfo.processInfo.environment
        environment.merge(extra) { $1 }
        return try await ProcessRunner.run(binary, arguments: arguments, environment: environment)
    }
}

/// Epic Games through legendary.
public actor EpicStore {
    public static let loginURL = URL(string: "https://legendary.gl/epiclogin")!

    let paths: AppPaths
    public init(paths: AppPaths = .default) { self.paths = paths }

    var configDirectory: URL { paths.root.appending(path: "Stores/legendary", directoryHint: .isDirectory) }
    private var environment: [String: String] { ["LEGENDARY_CONFIG_PATH": configDirectory.path] }

    public var isLoggedIn: Bool {
        FileManager.default.fileExists(atPath: configDirectory.appending(path: "user.json").path)
    }

    /// Signs in with the `authorizationCode` shown after logging in at `loginURL`.
    public func login(code: String) async throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let cleaned = Self.extractCode(code)
        let result = try await StoreTool.legendary.run(["auth", "--code", cleaned], paths: paths, environment: environment)
        guard result.succeeded, isLoggedIn else {
            throw KoprikError.commandFailed(command: "legendary auth", status: result.status, output: result.combinedOutput)
        }
    }

    public func logout() async {
        _ = try? await StoreTool.legendary.run(["auth", "--delete"], paths: paths, environment: environment)
    }

    /// Owned Windows games, with installed ones marked.
    public func library() async throws -> [StoreGame] {
        let result = try await StoreTool.legendary.run(["list", "--json", "--platform", "Windows"], paths: paths, environment: environment)
        guard result.succeeded else {
            throw KoprikError.commandFailed(command: "legendary list", status: result.status, output: result.combinedOutput)
        }
        let installed = installedGames()
        return Self.parseLibrary(result.stdout).map { game in
            var game = game
            game.installPath = installed[game.storeID]
            return game
        }
    }

    /// app_name -> install path, read straight from legendary's own record.
    public func installedGames() -> [String: String] {
        let file = configDirectory.appending(path: "installed.json")
        guard let data = try? Data(contentsOf: file),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        return object.compactMapValues { $0["install_path"] as? String }
    }

    /// Installs into the bottle's C: drive. `progress` receives 0...1.
    public func install(_ game: StoreGame, into bottle: Bottle, progress: @Sendable (Double) -> Void = { _ in }) async throws {
        let base = bottle.driveC.appending(path: "Games/Epic", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let result = try await StoreTool.legendary.run(
            ["-y", "install", game.storeID, "--base-path", base.path, "--platform", "Windows"],
            paths: paths, environment: environment
        )
        guard result.succeeded else {
            throw KoprikError.commandFailed(command: "legendary install \(game.storeID)", status: result.status, output: result.combinedOutput)
        }
        progress(1)
    }

    /// The executable, folder and arguments (including the short-lived
    /// sign-in token some games need) for starting a game ourselves.
    public func launch(_ appName: String, engine: Engine, bottle: Bottle) async throws -> StoreLaunch {
        let result = try await StoreTool.legendary.run(
            ["launch", appName, "--json", "--wine", engine.wineBinary.path, "--wine-prefix", bottle.prefix.path],
            paths: paths, environment: environment
        )
        guard result.succeeded, let launch = Self.parseLaunch(result.stdout) else {
            throw KoprikError.commandFailed(command: "legendary launch \(appName)", status: result.status, output: result.combinedOutput)
        }
        return launch
    }

    // MARK: Parsing

    /// The code may be pasted on its own or as the whole JSON the login page shows.
    static func extractCode(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = object["authorizationCode"] as? String {
            return code
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    static func parseLibrary(_ json: String) -> [StoreGame] {
        guard let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return array.compactMap { entry in
            guard let appName = entry["app_name"] as? String else { return nil }
            let title = entry["app_title"] as? String ?? appName
            let metadata = entry["metadata"] as? [String: Any]
            let images = metadata?["keyImages"] as? [[String: Any]] ?? []
            let cover = images.first { ($0["type"] as? String) == "DieselGameBoxTall" } ?? images.first
            return StoreGame(
                store: .epic, storeID: appName, title: title,
                coverURL: (cover?["url"] as? String).flatMap(URL.init(string:))
            )
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func parseLaunch(_ json: String) -> StoreLaunch? {
        // legendary may log lines before the JSON; take the outermost object.
        guard let start = json.firstIndex(of: "{"), let end = json.lastIndex(of: "}"),
              let data = String(json[start...end]).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let directory = object["game_directory"] as? String,
              let executable = object["game_executable"] as? String else { return nil }
        let folder = URL(fileURLWithPath: directory, isDirectory: true)
        let strings: (String) -> [String] = { (object[$0] as? [String]) ?? [] }
        let working = (object["working_directory"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
        return StoreLaunch(
            executable: folder.appending(path: executable),
            workingDirectory: working ?? folder,
            arguments: strings("game_parameters") + strings("user_parameters") + strings("egl_parameters")
        )
    }
}

/// GOG through heroic-gogdl, with the library read from GOG's Galaxy API.
public actor GOGStore {
    public static let clientID = "46899977096215655"
    /// The page that, after signing in, redirects to a URL containing `code=`.
    public static let loginURL = URL(string:
        "https://auth.gog.com/auth?client_id=\(clientID)&redirect_uri=https%3A%2F%2Fembed.gog.com%2Fon_login_success%3Forigin%3Dclient&response_type=code&layout=client2")!

    let paths: AppPaths
    public init(paths: AppPaths = .default) { self.paths = paths }

    var authFile: URL { paths.root.appending(path: "Stores/gog/auth.json") }

    public var isLoggedIn: Bool { FileManager.default.fileExists(atPath: authFile.path) }

    /// Accepts the bare code or the whole redirect URL pasted from the browser.
    public func login(code: String) async throws {
        try FileManager.default.createDirectory(at: authFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = try await StoreTool.gogdl.run(["--auth-config-path", authFile.path, "auth", "--code", Self.extractCode(code)], paths: paths)
        guard result.succeeded, isLoggedIn else {
            throw KoprikError.commandFailed(command: "gogdl auth", status: result.status, output: result.combinedOutput)
        }
    }

    public func logout() {
        try? FileManager.default.removeItem(at: authFile)
    }

    struct Credentials: Decodable {
        let access_token: String
        let user_id: String
    }

    /// Current credentials; gogdl refreshes them when they have expired.
    func credentials() async throws -> Credentials {
        let result = try await StoreTool.gogdl.run(["--auth-config-path", authFile.path, "auth"], paths: paths)
        guard result.succeeded,
              let start = result.stdout.firstIndex(of: "{"),
              let data = String(result.stdout[start...]).data(using: .utf8),
              let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            throw KoprikError.commandFailed(command: "gogdl auth", status: result.status, output: result.combinedOutput)
        }
        return credentials
    }

    public func library(installedIn bottles: [Bottle] = []) async throws -> [StoreGame] {
        let credentials = try await credentials()
        var ids: [String] = []
        var pageToken: String?
        repeat {
            var components = URLComponents(string: "https://galaxy-library.gog.com/users/\(credentials.user_id)/releases")!
            if let pageToken { components.queryItems = [URLQueryItem(name: "page_token", value: pageToken)] }
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(credentials.access_token)", forHTTPHeaderField: "Authorization")
            let (data, _) = try await URLSession.shared.data(for: request)
            let page = try JSONDecoder().decode(LibraryPage.self, from: data)
            ids += page.items.filter { $0.platform_id == "gog" && ($0.owned ?? true) }.map(\.external_id)
            pageToken = page.next_page_token
        } while pageToken != nil && ids.count < 5000

        let installed = Self.installedGames(in: bottles)
        var games: [StoreGame] = []
        await withTaskGroup(of: StoreGame?.self) { group in
            for id in Set(ids) {
                group.addTask { await Self.product(id: id) }
            }
            for await game in group {
                if var game {
                    game.installPath = installed[game.storeID]?.path
                    games.append(game)
                }
            }
        }
        return games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    struct LibraryPage: Decodable {
        struct Item: Decodable {
            let platform_id: String
            let external_id: String
            let owned: Bool?
        }
        let items: [Item]
        let next_page_token: String?
    }

    static func product(id: String) async -> StoreGame? {
        guard let url = URL(string: "https://api.gog.com/products/\(id)?expand=description"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              // DLCs and packs have no game of their own to launch.
              (object["game_type"] as? String ?? "game") == "game" else { return nil }
        let title = object["title"] as? String ?? id
        let images = object["images"] as? [String: Any]
        let cover = (images?["logo2x"] as? String).flatMap { URL(string: $0.hasPrefix("//") ? "https:" + $0 : $0) }
        return StoreGame(store: .gog, storeID: id, title: title, coverURL: cover)
    }

    public func install(_ game: StoreGame, into bottle: Bottle) async throws {
        let base = bottle.driveC.appending(path: "Games/GOG", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let result = try await StoreTool.gogdl.run(
            ["--auth-config-path", authFile.path, "download", game.storeID, "--platform", "windows", "--path", base.path],
            paths: paths
        )
        guard result.succeeded else {
            throw KoprikError.commandFailed(command: "gogdl download \(game.storeID)", status: result.status, output: result.combinedOutput)
        }
    }

    // MARK: Installed games

    /// GOG games found in the bottles, keyed by product id, from the
    /// `goggame-<id>.info` file every GOG install carries.
    static func installedGames(in bottles: [Bottle]) -> [String: URL] {
        var found: [String: URL] = [:]
        let manager = FileManager.default
        for bottle in bottles {
            let base = bottle.driveC.appending(path: "Games/GOG", directoryHint: .isDirectory)
            for folder in (try? manager.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? [] {
                for file in (try? manager.contentsOfDirectory(atPath: folder.path)) ?? []
                where file.hasPrefix("goggame-") && file.hasSuffix(".info") {
                    let id = String(file.dropFirst("goggame-".count).dropLast(".info".count))
                    found[id] = folder
                }
            }
        }
        return found
    }

    /// How to start a GOG game, from the primary play task in its info file.
    public static func launch(installedAt folder: URL, id: String) -> StoreLaunch? {
        guard let data = try? Data(contentsOf: folder.appending(path: "goggame-\(id).info")) else { return nil }
        return parseInfo(data, folder: folder)
    }

    static func parseInfo(_ data: Data, folder: URL) -> StoreLaunch? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = object["playTasks"] as? [[String: Any]] else { return nil }
        let fileTasks = tasks.filter { ($0["type"] as? String ?? "FileTask") == "FileTask" && $0["path"] != nil }
        guard let task = fileTasks.first(where: { $0["isPrimary"] as? Bool == true }) ?? fileTasks.first,
              let path = task["path"] as? String else { return nil }
        let relative = path.replacingOccurrences(of: "\\", with: "/")
        let working = (task["workingDir"] as? String).map { $0.replacingOccurrences(of: "\\", with: "/") } ?? ""
        let arguments: [String] = if let list = task["arguments"] as? [String] {
            list
        } else if let line = task["arguments"] as? String {
            ProgramStore.splitArguments(line)
        } else {
            []
        }
        let executable = folder.appending(path: relative)
        return StoreLaunch(
            executable: executable,
            workingDirectory: working.isEmpty ? executable.deletingLastPathComponent() : folder.appending(path: working, directoryHint: .isDirectory),
            arguments: arguments
        )
    }

    static func extractCode(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: trimmed),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value {
            return code
        }
        return trimmed
    }
}
