import Foundation

/// Instructions for installing one piece of Windows software unattended.
///
/// Recipes are plain JSON, so new ones can be dropped into the `Recipes`
/// folder without rebuilding the app.
public struct Recipe: Codable, Sendable, Equatable, Identifiable {
    public enum Category: String, Codable, Sendable, CaseIterable {
        case store, productivity, utility, runtime
    }

    public struct Download: Codable, Sendable, Equatable {
        public var url: URL
        public var fileName: String
        /// Lowercase hex. Left out for installers whose publisher replaces the
        /// file in place with every release, as game launchers do.
        public var sha256: String?

        public init(url: URL, fileName: String, sha256: String? = nil) {
            self.url = url
            self.fileName = fileName
            self.sha256 = sha256
        }
    }

    public var id: String
    public var name: String
    public var category: Category
    public var summary: String
    public var windowsVersion: WindowsVersion
    /// Winetricks verbs to install before the program itself.
    public var winetricks: [String]
    public var download: Download?
    /// Arguments that make the installer run without questions.
    public var installerArguments: [String]
    /// Settings stored on the bottle the recipe creates.
    public var settings: LaunchSettings
    /// Windows path of the main program once installed.
    public var executable: String?
    /// Whether the recipe has been run successfully on this project's test Mac.
    public var tested: Bool
    public var notes: String?

    public init(
        id: String, name: String, category: Category, summary: String,
        windowsVersion: WindowsVersion = .win10, winetricks: [String] = [],
        download: Download? = nil, installerArguments: [String] = [],
        settings: LaunchSettings = LaunchSettings(), executable: String? = nil,
        tested: Bool = false, notes: String? = nil
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.summary = summary
        self.windowsVersion = windowsVersion
        self.winetricks = winetricks
        self.download = download
        self.installerArguments = installerArguments
        self.settings = settings
        self.executable = executable
        self.tested = tested
        self.notes = notes
    }
}

public enum RecipeLibrary {
    /// Recipes that ship with Ko'prik.
    public static let builtin: [Recipe] = [
        Recipe(
            id: "steam", name: "Steam", category: .store,
            summary: "Valve's game store and library.",
            download: .init(url: URL(string: "https://cdn.akamai.steamstatic.com/client/installer/SteamSetup.exe")!, fileName: "SteamSetup.exe"),
            installerArguments: ["/S"],
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files (x86)\\Steam\\steam.exe",
            tested: true,
            notes: "The first start downloads the full client, about 400 MB."
        ),
        Recipe(
            id: "epic", name: "Epic Games Launcher", category: .store,
            summary: "Epic's store. Fortnite itself does not run: its anti-cheat blocks Wine.",
            download: .init(url: URL(string: "https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi")!, fileName: "EpicGamesLauncherInstaller.msi"),
            installerArguments: ["/q"],
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files (x86)\\Epic Games\\Launcher\\Portal\\Binaries\\Win64\\EpicGamesLauncher.exe"
        ),
        Recipe(
            id: "gog-galaxy", name: "GOG Galaxy", category: .store,
            summary: "GOG's launcher for DRM-free games.",
            download: .init(url: URL(string: "https://webinstallers.gog-statics.com/download/GOG_Galaxy_2.0.exe")!, fileName: "GOG_Galaxy_2.0.exe"),
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files (x86)\\GOG Galaxy\\GalaxyClient.exe"
        ),
        Recipe(
            id: "battlenet", name: "Battle.net", category: .store,
            summary: "Blizzard's launcher. Call of Duty does not run: its anti-cheat blocks Wine.",
            download: .init(url: URL(string: "https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe")!, fileName: "Battle.net-Setup.exe"),
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files (x86)\\Battle.net\\Battle.net Launcher.exe"
        ),
        Recipe(
            id: "ea-app", name: "EA app", category: .store,
            summary: "Electronic Arts' launcher.",
            download: .init(url: URL(string: "https://origin-a.akamaihd.net/EA-Desktop-Client-Download/installer-releases/EAappInstaller.exe")!, fileName: "EAappInstaller.exe"),
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files\\Electronic Arts\\EA Desktop\\EA Desktop\\EALauncher.exe"
        ),
        Recipe(
            id: "ubisoft-connect", name: "Ubisoft Connect", category: .store,
            summary: "Ubisoft's launcher.",
            download: .init(url: URL(string: "https://static3.cdn.ubi.com/orbit/launcher_installer/UbisoftConnectInstaller.exe")!, fileName: "UbisoftConnectInstaller.exe"),
            installerArguments: ["/S"],
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files (x86)\\Ubisoft\\Ubisoft Game Launcher\\UbisoftConnect.exe"
        ),
        Recipe(
            id: "rockstar", name: "Rockstar Games Launcher", category: .store,
            summary: "Rockstar's launcher.",
            download: .init(url: URL(string: "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe")!, fileName: "Rockstar-Games-Launcher.exe"),
            settings: LaunchSettings(backend: .dxmt),
            executable: "C:\\Program Files\\Rockstar Games\\Launcher\\Launcher.exe"
        ),
        Recipe(
            id: "7zip", name: "7-Zip", category: .utility,
            summary: "File archiver.",
            download: .init(
                url: URL(string: "https://www.7-zip.org/a/7z2409-x64.exe")!, fileName: "7z2409-x64.exe",
                sha256: "bdd1a33de78618d16ee4ce148b849932c05d0015491c34887846d431d29f308e"
            ),
            installerArguments: ["/S"],
            executable: "C:\\Program Files\\7-Zip\\7zFM.exe",
            tested: true
        ),
        Recipe(
            id: "gaming-essentials", name: "Gaming essentials", category: .runtime,
            summary: "Fonts, Visual C++ runtime and DirectX helper libraries that many games expect.",
            winetricks: ["corefonts", "vcrun2022", "d3dcompiler_47"]
        ),
        Recipe(
            id: "dotnet48", name: ".NET Framework 4.8", category: .runtime,
            summary: "Microsoft's runtime for older .NET programs. Takes several minutes.",
            winetricks: ["dotnet48"]
        ),
    ]

    /// Built-in recipes plus any `*.json` found in `directory`; a file with the
    /// same `id` as a built-in recipe replaces it.
    public static func all(extraDirectory directory: URL? = nil) -> [Recipe] {
        var byID = Dictionary(uniqueKeysWithValues: builtin.map { ($0.id, $0) })
        if let directory,
           let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let recipe = try? JSONDecoder().decode(Recipe.self, from: Data(contentsOf: file)) {
                    byID[recipe.id] = recipe
                }
            }
        }
        return byID.values.sorted { ($0.category.rawValue, $0.name) < ($1.category.rawValue, $1.name) }
    }
}

/// Progress of an installation, for display.
public enum InstallStage: Sendable, Equatable {
    case snapshotting
    case downloading(fraction: Double?)
    case verifying
    case runningWinetricks(String)
    case runningInstaller
    case finished
}

/// Runs recipes and loose installer files inside a bottle.
public struct Installer: Sendable {
    public let bottle: Bottle
    public let engine: Engine
    public let paths: AppPaths

    public init(bottle: Bottle, engine: Engine, paths: AppPaths = .default) {
        self.bottle = bottle
        self.engine = engine
        self.paths = paths
    }

    /// Installs a recipe. A snapshot is taken first when the bottle already
    /// holds something, so a bad install can be undone.
    public func install(
        _ recipe: Recipe,
        snapshotFirst: Bool = true,
        progress: @Sendable @escaping (InstallStage) -> Void = { _ in }
    ) async throws {
        let launcher = Launcher(bottle: bottle, engine: engine)
        if snapshotFirst {
            progress(.snapshotting)
            await launcher.stopAll()
            _ = try await BottleStore(paths: paths).snapshot(bottle, label: "Before \(recipe.name)")
        }

        if !recipe.winetricks.isEmpty {
            progress(.runningWinetricks(recipe.winetricks.joined(separator: " ")))
            try await Winetricks(paths: paths).run(verbs: recipe.winetricks, bottle: bottle, engine: engine)
        }

        if let download = recipe.download {
            try paths.ensureDirectories()
            let file = paths.installers.appending(path: download.fileName)
            let cached = FileManager.default.fileExists(atPath: file.path)
            // Launcher installers change without notice, so only pinned files are reused.
            if !(cached && download.sha256 != nil) {
                progress(.downloading(fraction: nil))
                try await Downloader.download(download.url, to: file) { progress(.downloading(fraction: $0.fraction)) }
            }
            if let expected = download.sha256 {
                progress(.verifying)
                let actual = try Checksum.sha256(of: file)
                guard actual == expected.lowercased() else {
                    try? FileManager.default.removeItem(at: file)
                    throw KoprikError.checksumMismatch(expected: expected, actual: actual)
                }
            }
            progress(.runningInstaller)
            let launch = try await launcher.launch(.file(file, arguments: recipe.installerArguments))
            let status = await launch.process.waitUntilExit()
            // Many installers end by starting the program they installed and
            // report odd exit codes; a missing executable is the real failure.
            if let executable = recipe.executable,
               let installed = WindowsPath.hostURL(for: executable, prefix: bottle.prefix),
               !FileManager.default.fileExists(atPath: installed.path) {
                throw KoprikError.commandFailed(
                    command: download.fileName, status: status,
                    output: BottleStore.tail(of: launch.process.logURL)
                )
            }
        }
        progress(.finished)
    }
}

/// Wraps the winetricks script, which installs Microsoft runtimes and fonts.
public struct Winetricks: Sendable {
    public static let scriptURL = URL(string: "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks")!

    /// Verbs worth offering in the interface, with what they provide.
    public static let commonVerbs: [(verb: String, title: String)] = [
        ("corefonts", "Microsoft core fonts (Arial, Times New Roman, ...)"),
        ("vcrun2022", "Visual C++ 2015-2022 runtime"),
        ("vcrun2013", "Visual C++ 2013 runtime"),
        ("vcrun2010", "Visual C++ 2010 runtime"),
        ("d3dcompiler_47", "Direct3D shader compiler 47"),
        ("d3dx9", "DirectX 9 helper libraries"),
        ("d3dx11_43", "DirectX 11 helper library"),
        ("xact", "XACT/XAudio audio libraries"),
        ("dotnet48", ".NET Framework 4.8"),
        ("dotnetdesktop8", ".NET Desktop Runtime 8"),
        ("mfc42", "Visual C++ 6 MFC libraries"),
        ("gdiplus", "GDI+ graphics library"),
        ("physx", "NVIDIA PhysX"),
        ("faudio", "FAudio (XAudio reimplementation)"),
        ("tahoma", "Tahoma font"),
        ("cjkfonts", "Chinese, Japanese and Korean fonts"),
    ]

    public let paths: AppPaths

    public init(paths: AppPaths = .default) {
        self.paths = paths
    }

    public var scriptFile: URL { paths.cache.appending(path: "winetricks") }

    /// Tools winetricks calls and macOS does not ship.
    public static func missingTools() -> [String] {
        let searchPath = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        return ["cabextract"].filter { tool in
            !searchPath.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(tool)") }
        }
    }

    /// Downloads the script when it is missing or older than a week.
    public func ensureScript() async throws -> URL {
        let manager = FileManager.default
        try paths.ensureDirectories()
        if let modified = try? manager.attributesOfItem(atPath: scriptFile.path)[.modificationDate] as? Date,
           Date.now.timeIntervalSince(modified) < 7 * 86_400 {
            return scriptFile
        }
        do {
            try await Downloader.download(Self.scriptURL, to: scriptFile)
            try manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
        } catch {
            // An older copy is better than none when offline.
            guard manager.fileExists(atPath: scriptFile.path) else { throw error }
        }
        return scriptFile
    }

    /// Installs verbs into the bottle, unattended. Returns the log file.
    @discardableResult
    public func run(verbs: [String], bottle: Bottle, engine: Engine) async throws -> URL {
        let missing = Self.missingTools()
        guard missing.isEmpty else {
            throw KoprikError.invalidArgument("winetricks needs \(missing.joined(separator: ", ")). Install with: brew install \(missing.joined(separator: " "))")
        }
        let script = try await ensureScript()
        var environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: LaunchSettings())
        environment["WINE"] = engine.wineBinary.path
        environment["WINESERVER"] = engine.wineserverBinary.path
        environment["PATH"] = engine.binDirectory.path + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["W_OPT_UNATTENDED"] = "1"

        let log = bottle.newLogURL(label: "winetricks-" + verbs.joined(separator: "-"))
        let manager = FileManager.default
        try manager.createDirectory(at: bottle.logs, withIntermediateDirectories: true)
        manager.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, "-q"] + verbs
        process.environment = environment
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else {
            throw KoprikError.commandFailed(command: "winetricks \(verbs.joined(separator: " "))", status: status, output: BottleStore.tail(of: log))
        }
        return log
    }
}
