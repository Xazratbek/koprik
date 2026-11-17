import Foundation

/// What to start in a bottle.
public enum LaunchTarget: Sendable, Equatable {
    /// A program from the bottle's library.
    case program(Program)
    /// A file on the Mac: `.exe`, `.msi`, `.bat` or `.lnk`.
    case file(URL, arguments: [String])
    /// A program by its Windows name or path, for example `winecfg` or `C:\app\app.exe`.
    case command(String, arguments: [String])

    var label: String {
        switch self {
        case .program(let program): program.name
        case .file(let url, _): url.lastPathComponent
        case .command(let name, _): name
        }
    }
}

/// The outcome of preparing and starting a launch.
public struct Launch: Sendable {
    public let process: WineProcess
    public let graphics: GraphicsDecision
    public let settings: LaunchSettings
    public let environment: [String: String]
    public let arguments: [String]
}

/// Starts programs: resolves the settings layers, picks the graphics backend,
/// readies the bottle for it and runs Wine.
///
/// Both the app and the command-line tool go through here, so a program
/// behaves the same wherever it is started from.
public struct Launcher: Sendable {
    public let bottle: Bottle
    public let engine: Engine

    public init(bottle: Bottle, engine: Engine) {
        self.bottle = bottle
        self.engine = engine
    }

    /// Settings for helper processes (taskkill, wineserver, winetricks). They
    /// must match the running server's synchronisation mode, or Wine refuses
    /// them: "Server is running with WINEMSYNC but this process is not" (B11).
    public static func baseSettings(engine: Engine, bottle: Bottle) -> LaunchSettings {
        let full = LaunchSettings.resolve([engine.defaultSettings, bottle.config.settings])
        return LaunchSettings(sync: full.sync)
    }

    /// The settings a target would run with, lowest layer first:
    /// engine defaults, the bottle, the program, then one-off overrides.
    public func resolvedSettings(for target: LaunchTarget, overrides: LaunchSettings = LaunchSettings()) -> LaunchSettings {
        var layers = [engine.defaultSettings, bottle.config.settings]
        if case .program(let program) = target { layers.append(program.settings) }
        layers.append(overrides)
        return LaunchSettings.resolve(layers)
    }

    /// The backend a target would run on, without starting anything.
    public func graphicsDecision(for target: LaunchTarget, overrides: LaunchSettings = LaunchSettings()) -> GraphicsDecision {
        decide(for: target, settings: resolvedSettings(for: target, overrides: overrides))
    }

    /// Store launchers draw their interface with Chromium, whose GPU process
    /// presents into a window owned by another process. DXMT does not support
    /// that ("cross-process swapchain not supported yet") and wined3d fails to
    /// link Chromium's shaders, so both leave the window black. DXVK works.
    /// Measured with the Steam client on winecx-gptk 4.8.3; see docs/SINOV.md.
    private func decide(for target: LaunchTarget, settings: LaunchSettings) -> GraphicsDecision {
        if (settings.backend ?? .auto) == .auto, Graphics.capabilities(of: engine).dxvk {
            if isStoreLauncher(target) {
                return GraphicsDecision(
                    backend: .dxvk,
                    reason: "Store launchers draw with Chromium, which only renders correctly on DXVK."
                )
            }
            if executables(of: target).contains(where: Self.isChromiumApp) {
                return GraphicsDecision(
                    backend: .dxvk,
                    reason: "Built on Chromium or Electron, which draws a blank window on DXMT and correctly on DXVK."
                )
            }
        }
        return Graphics.decide(requested: settings.backend, engine: engine, executables: executables(of: target))
    }

    public func launch(
        _ target: LaunchTarget,
        overrides: LaunchSettings = LaunchSettings(),
        wait: Bool = true
    ) async throws -> Launch {
        // An isolated bottle cannot read the Mac's folders, so a file from
        // outside (an installer in Downloads, say) is copied in and run from there.
        var target = target
        if (bottle.config.isolation ?? .off).isOn, case .file(let url, let extra) = target,
           !url.standardizedFileURL.path.hasPrefix(bottle.directory.standardizedFileURL.path) {
            target = .file(try importIntoBottle(url), arguments: extra)
        }
        if (bottle.config.isolation ?? .off).isOn { await sealBottle() }

        var settings = resolvedSettings(for: target, overrides: overrides)
        let decision = decide(for: target, settings: settings)
        settings.backend = decision.backend
        // The user's own overrides still win over these.
        settings.dllOverrides = Graphics.overridesAvoidingD3DMetal(for: decision.backend, engine: engine)
            .merging(settings.dllOverrides ?? [:]) { _, user in user }

        // Engines installed before the Game Mode bundle existed get it now.
        if GameBundle.loader(for: engine) == nil, engine.manifest.d3dmetalCapable {
            _ = try? await GameBundle.build(for: engine)
        }
        await applyDisplayMode()

        let runner = WineRunner.forBottle(bottle, engine: engine)
        var environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: settings)

        // Steam games are started directly rather than through `steam.exe
        // -applaunch`: a game started by Steam inherits the client's
        // environment and DLLs, so per-game settings would have no effect.
        // The game still needs the client running to sign in to Steam.
        var steamGame: (executable: URL, appID: Int)?
        if case .program(let program) = target, program.kind == .steam, let appID = program.steamAppID,
           let executable = Self.mainExecutable(ofSteamGameAt: URL(fileURLWithPath: program.location)) {
            try await ensureSteamClientRunning()
            steamGame = (executable, appID)
            environment["SteamAppId"] = String(appID)
            environment["SteamGameId"] = String(appID)
            environment["SteamOverlayGameId"] = String(appID)
        }

        // Epic and GOG games are started directly too, with what their store tool reports.
        var storeLaunch: StoreLaunch?
        if case .program(let program) = target, let storeID = program.storeID {
            switch program.kind {
            case .epic:
                storeLaunch = try await EpicStore().launch(storeID, engine: engine, bottle: bottle)
            case .gog:
                storeLaunch = GOGStore.launch(installedAt: URL(fileURLWithPath: program.location), id: storeID)
            case .executable, .steam:
                break
            }
        }

        // The DLLs in system32 serve every program in the bottle. While other
        // programs run (Steam, typically, which needs DXVK), they stay as they
        // are and this program gets its backend from its own folder instead:
        // Windows looks for DLLs next to the executable first.
        // Only folders inside the bottle: Ko'prik never writes DLLs next to a
        // program that lives elsewhere on the Mac (B23 in docs/SINOV.md).
        let bottleRoot = bottle.directory.standardizedFileURL.path
        let localDirectory = (steamGame?.executable.deletingLastPathComponent()
            ?? storeLaunch?.executable.deletingLastPathComponent()
            ?? executableDirectory(of: target))
            .flatMap { $0.standardizedFileURL.path.hasPrefix(bottleRoot) ? $0 : nil }
        if !BottleActivity.isRunning(bottle) {
            try Graphics.prepare(decision.backend, engine: engine, prefix: bottle.prefix)
            BottleActivity.setActiveBackend(decision.backend, of: bottle)
            if let localDirectory { try Graphics.clearLocal(in: localDirectory) }
        } else if let localDirectory {
            if BottleActivity.activeBackend(of: bottle) == decision.backend {
                try Graphics.clearLocal(in: localDirectory)
            } else {
                try Graphics.prepareLocal(decision.backend, engine: engine, directory: localDirectory)
            }
        } else if BottleActivity.activeBackend(of: bottle) != decision.backend {
            try Graphics.prepare(decision.backend, engine: engine, prefix: bottle.prefix)
            BottleActivity.setActiveBackend(decision.backend, of: bottle)
        }

        let arguments: [String]
        var workingDirectory: URL?
        switch target {
        case .file(let url, let extra):
            arguments = WineRunner.startArguments(for: url, programArguments: extra, wait: wait)
            workingDirectory = url.deletingLastPathComponent()
        case .command(let name, let extra):
            arguments = [name] + extra
        case .program(let program):
            switch program.kind {
            case .executable:
                guard let url = program.executableURL(in: bottle) else {
                    throw KoprikError.invalidArgument("Cannot locate \(program.location) in the bottle.")
                }
                arguments = WineRunner.startArguments(for: url, programArguments: program.arguments, wait: wait)
                workingDirectory = url.deletingLastPathComponent()
            case .epic, .gog:
                guard let storeLaunch else {
                    throw KoprikError.invalidArgument("Cannot find how to start \(program.name). Reinstall it from the store page.")
                }
                arguments = WineRunner.startArguments(for: storeLaunch.executable, programArguments: storeLaunch.arguments + program.arguments, wait: wait)
                workingDirectory = storeLaunch.workingDirectory
            case .steam:
                if let steamGame {
                    arguments = WineRunner.startArguments(for: steamGame.executable, programArguments: program.arguments, wait: wait)
                    workingDirectory = steamGame.executable.deletingLastPathComponent()
                } else {
                    // No obvious game executable: let Steam decide how to start it.
                    guard let steam = SteamLibrary.steamDirectory(in: bottle), let appID = program.steamAppID else {
                        throw KoprikError.invalidArgument("Steam is not installed in this bottle.")
                    }
                    arguments = [steamClientPath(steam), "-applaunch", String(appID)] + program.arguments
                    workingDirectory = steam
                }
            }
        }

        // DXVK 1.10.3 takes a frame cap only from a config file.
        if decision.backend == .dxvk, let rate = settings.maxFrameRate, rate > 0 {
            let file = bottle.directory.appending(path: "dxvk-\(rate).conf")
            if !FileManager.default.fileExists(atPath: file.path) {
                try? "dxgi.maxFrameRate = \(rate)\nd3d9.maxFrameRate = \(rate)\n".write(to: file, atomically: true, encoding: .utf8)
            }
            environment["DXVK_CONFIG_FILE"] = file.path
        }

        if isSteamClient(target) {
            // Steam's own interface is a Chromium view; async shader compilation keeps it responsive.
            environment["DXVK_ASYNC"] = environment["DXVK_ASYNC"] ?? "1"
            SteamLibrary.setGameOverlay(enabled: false, in: bottle)
        }

        let process = try runner.launch(
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            logURL: bottle.newLogURL(label: target.label)
        )
        return Launch(process: process, graphics: decision, settings: settings, environment: environment, arguments: arguments)
    }

    /// Copies a file from the Mac into the bottle's Public Downloads folder (C:\\users\\Public\\Downloads\\Koprik).
    func importIntoBottle(_ url: URL) throws -> URL {
        let folder = bottle.driveC.appending(path: "users/Public/Downloads/Koprik", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            if manager.contentsEqual(atPath: url.path, andPath: destination.path) { return destination }
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: url, to: destination)
        return destination
    }

    /// Removes the drive letters and folder links that point out of an
    /// isolated bottle, once. The sandbox already blocks them; this keeps
    /// Windows programs from even seeing the Mac's disk.
    private func sealBottle() async {
        let marker = bottle.directory.appending(path: ".sealed")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        do {
            try BottleTools(bottle: bottle, engine: engine).restrictFileAccess()
            FileManager.default.createFile(atPath: marker.path, contents: nil)
        } catch {
            // The sandbox still protects the Mac if this fails.
        }
    }

    /// Writes the bottle's full-screen mode into Wine's Mac driver settings,
    /// once per change. The driver reads it when each program starts.
    private func applyDisplayMode() async {
        let capture = (bottle.config.exclusiveFullscreen ?? true) ? "Y" : "N"
        let retina = (bottle.config.highResolution ?? true) ? "Y" : "N"
        let wanted = "capture=\(capture);retina=\(retina)"
        let marker = bottle.directory.appending(path: ".display-mode")
        if (try? String(contentsOf: marker, encoding: .utf8)) == wanted { return }
        let environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: Self.baseSettings(engine: engine, bottle: bottle))
        let runner = WineRunner.forBottle(bottle, engine: engine)
        let log = bottle.newLogURL(label: "display-mode")
        let macDriver = "HKCU\\Software\\Wine\\Mac Driver"
        let commands: [[String]] = [
            ["reg", "add", macDriver, "/v", "CaptureDisplaysForFullscreen", "/t", "REG_SZ", "/d", capture, "/f"],
            // Retina: Wine draws at the panel's pixel resolution, and Windows
            // scales its interface to 200% (192 DPI) so it keeps its size.
            ["reg", "add", macDriver, "/v", "RetinaMode", "/t", "REG_SZ", "/d", retina, "/f"],
            ["reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "LogPixels", "/t", "REG_DWORD", "/d", retina == "Y" ? "192" : "96", "/f"],
            ["reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "FontSmoothing", "/t", "REG_SZ", "/d", "2", "/f"],
            ["reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "FontSmoothingType", "/t", "REG_DWORD", "/d", "2", "/f"],
        ]
        var succeeded = true
        for command in commands {
            let status = try? await runner.run(command, environment: environment, logURL: log)
            if status != 0 { succeeded = false }
        }
        if succeeded { try? wanted.write(to: marker, atomically: true, encoding: .utf8) }
    }

    /// Starts the Windows Steam client in the background if it is not running,
    /// and waits until it can serve games.
    public func ensureSteamClientRunning(timeout: Duration = .seconds(60)) async throws {
        guard let steam = SteamLibrary.steamDirectory(in: bottle) else {
            throw KoprikError.invalidArgument("Steam is not installed in this bottle.")
        }
        if await BottleActivity.isProcessRunning(named: "steam.exe") { return }

        // A webhelper left over from a crashed client blocks a new one (see B2 in docs/SINOV.md).
        if await BottleActivity.isProcessRunning(named: "steamwebhelper.exe") { await stopAll() }

        SteamLibrary.setGameOverlay(enabled: false, in: bottle)
        if !BottleActivity.isRunning(bottle) {
            try Graphics.prepare(.dxvk, engine: engine, prefix: bottle.prefix)
            BottleActivity.setActiveBackend(.dxvk, of: bottle)
        }
        _ = try WineRunner.forBottle(bottle, engine: engine).launch(
            [steamClientPath(steam), "-silent"],
            environment: WineEnvironment.build(
                engine: engine, prefix: bottle.prefix,
                settings: LaunchSettings.resolve([engine.defaultSettings, bottle.config.settings, LaunchSettings(backend: .dxvk)])
            ),
            workingDirectory: steam,
            logURL: bottle.newLogURL(label: "Steam")
        )
        // A game whose client is not signed in yet fails SteamAPI_Init and
        // aborts (c0000409), so wait for Steam's own "Logged On" line.
        let connectionLog = steam.appending(path: "logs/connection_log.txt")
        let alreadyLogged = (try? FileManager.default.attributesOfItem(atPath: connectionLog.path)[.size] as? NSNumber)?.intValue ?? 0
        let deadline = ContinuousClock.now + timeout
        var helperSeen: ContinuousClock.Instant?
        while ContinuousClock.now < deadline {
            if let handle = try? FileHandle(forReadingFrom: connectionLog) {
                try? handle.seek(toOffset: UInt64(alreadyLogged))
                let fresh = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
                try? handle.close()
                if fresh.contains("[Logged On") {
                    try? await Task.sleep(for: .seconds(2))
                    return
                }
            }
            // Offline, or signed out: once the interface is up there is nothing more to wait for.
            if helperSeen == nil, await BottleActivity.isProcessRunning(named: "steamwebhelper.exe") {
                helperSeen = .now
            }
            if let helperSeen, ContinuousClock.now - helperSeen > .seconds(20) { return }
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// The Steam client as a Windows path. Started by a Unix path, Wine shows
    /// the process under that path in `ps`, where it is not recognised as a
    /// Windows program (and Steam was started six times over before this).
    private func steamClientPath(_ steam: URL) -> String {
        let client = steam.appending(path: "steam.exe")
        return WindowsPath.windowsPath(for: client, prefix: bottle.prefix) ?? client.path
    }

    /// Closes one program the way Windows would (a close request first, then
    /// termination), leaving the rest of the bottle running.
    public func stop(programNamed executableName: String) async {
        let environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: Launcher.baseSettings(engine: engine, bottle: bottle))
        let runner = WineRunner.forBottle(bottle, engine: engine)
        let log = bottle.newLogURL(label: "stop")
        _ = try? await runner.run(["taskkill", "/IM", executableName], environment: environment, logURL: log)
        await BottleActivity.waitForProcess(named: executableName, toExitWithin: .seconds(10))
        if await BottleActivity.isProcessRunning(named: executableName) {
            _ = try? await runner.run(["taskkill", "/F", "/IM", executableName], environment: environment, logURL: log)
        }
    }

    /// The executable a Steam game is most likely started with.
    ///
    /// In order: an executable named like the game's folder (Brawlhalla's is
    /// a 185 KB stub, so size alone misleads), then the largest one near the
    /// top of the folder, then the largest anywhere.
    public static func mainExecutable(ofSteamGameAt folder: URL) -> URL? {
        let candidates = gameExecutables(in: folder, limit: 16, minimumSize: 64 * 1024)
        let folderName = normalized(folder.lastPathComponent)
        if let named = candidates.first(where: {
            let name = normalized($0.deletingPathExtension().lastPathComponent)
            return name == folderName || (name.count > 3 && folderName.hasPrefix(name)) || (folderName.count > 3 && name.hasPrefix(folderName))
        }) {
            return named
        }
        let depth = folder.standardizedFileURL.pathComponents.count
        let shallow = candidates.filter { $0.deletingLastPathComponent().standardizedFileURL.pathComponents.count <= depth + 2 }
        return shallow.first ?? candidates.first
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// The folder of the executable the target runs, where DLLs placed next to it take effect.
    private func executableDirectory(of target: LaunchTarget) -> URL? {
        switch target {
        case .file(let url, _):
            url.pathExtension.lowercased() == "exe" ? url.deletingLastPathComponent() : nil
        case .program(let program) where program.kind == .executable:
            program.executableURL(in: bottle).map { $0.deletingLastPathComponent() }
        case .program, .command:
            nil
        }
    }

    /// Stops everything running in the bottle.
    public func stopAll() async {
        let environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: Launcher.baseSettings(engine: engine, bottle: bottle))
        // `wineserver -k` exits non-zero when nothing was running, which is fine here.
        _ = try? await WineRunner.forBottle(bottle, engine: engine)
            .wineserver(["-k"], environment: environment, logURL: bottle.newLogURL(label: "kill"))
        await BottleActivity.killOrphans(of: bottle)
    }

    // MARK: Helpers

    /// Whether an executable is a Chromium or Electron app (Notion, Discord,
    /// Slack, Spotify, Teams, VS Code ...). They ship Chromium's resource
    /// packs and ANGLE beside the executable.
    static func isChromiumApp(_ executable: URL) -> Bool {
        let folder = executable.deletingLastPathComponent()
        let manager = FileManager.default
        let markers = ["chrome_100_percent.pak", "resources.pak", "libEGL.dll", "resources/app.asar", "snapshot_blob.bin"]
        return markers.filter { manager.fileExists(atPath: folder.appending(path: $0).path) }.count >= 2
    }

    /// Executables of launchers whose interface is a Chromium view.
    private static let storeLauncherNames: Set<String> = [
        "steam.exe", "steamwebhelper.exe", "epicgameslauncher.exe", "galaxyclient.exe", "battle.net.exe",
        "battle.net launcher.exe", "eadesktop.exe", "ealauncher.exe", "ubisoftconnect.exe", "upc.exe",
    ]

    private func isStoreLauncher(_ target: LaunchTarget) -> Bool {
        let path: String
        switch target {
        case .program(let program):
            // Games from Steam are not launchers: they are started directly
            // and pick their backend like any other program.
            if program.kind == .steam { return false }
            path = program.location
        case .file(let url, _):
            path = url.path
        case .command(let name, _):
            path = name
        }
        let lowered = path.lowercased().replacingOccurrences(of: "\\", with: "/")
        let name = lowered.split(separator: "/").last.map(String.init) ?? lowered
        return Self.storeLauncherNames.contains(name) || lowered.contains("rockstar games/launcher")
    }

    private func isSteamClient(_ target: LaunchTarget) -> Bool {
        switch target {
        case .program(let program):
            program.kind == .steam || program.location.lowercased().hasSuffix("steam.exe")
        case .file(let url, _):
            url.lastPathComponent.lowercased() == "steam.exe"
        case .command(let name, _):
            name.lowercased().hasSuffix("steam.exe")
        }
    }

    /// Files whose import tables tell which Direct3D version the target uses.
    private func executables(of target: LaunchTarget) -> [URL] {
        switch target {
        case .file(let url, _):
            return url.pathExtension.lowercased() == "exe" ? [url] : []
        case .command(let name, _):
            return WindowsPath.hostURL(for: name, prefix: bottle.prefix).map { [$0] } ?? []
        case .program(let program):
            switch program.kind {
            case .executable:
                return program.executableURL(in: bottle).map { [$0] } ?? []
            case .steam, .epic:
                return Self.gameExecutables(in: URL(fileURLWithPath: program.location))
            case .gog:
                let folder = URL(fileURLWithPath: program.location)
                if let storeID = program.storeID, let launch = GOGStore.launch(installedAt: folder, id: storeID) {
                    return [launch.executable]
                }
                return Self.gameExecutables(in: folder)
            }
        }
    }

    /// The larger executables in a game folder, a few levels deep. Small files
    /// are skipped: they are crash reporters, redistributable installers and
    /// the like, and would only blur the picture.
    public static func gameExecutables(in folder: URL, limit: Int = 12, minimumSize: Int = 512 * 1024) -> [URL] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [(url: URL, size: Int)] = []
        for case let url as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "exe",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let size = values.fileSize, size > minimumSize else { continue }
            let lowered = url.lastPathComponent.lowercased()
            if ["redist", "setup", "install", "crash", "unins", "vc_", "dxsetup", "dotnet"].contains(where: lowered.contains) { continue }
            found.append((url, size))
        }
        return found.sorted { $0.size > $1.size }.prefix(limit).map(\.url)
    }
}

/// What is going on inside a bottle right now, read from the outside.
public enum BottleActivity {
    /// Whether a `wineserver` is serving the bottle.
    ///
    /// Wine keeps a socket for each prefix under `/tmp/.wine-<uid>/`, in a
    /// folder named after the prefix directory's device and inode numbers.
    public static func isRunning(_ bottle: Bottle) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: bottle.prefix.path),
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else { return false }
        let socket = "/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))/socket"
        // The socket file outlives a killed server, so existence proves
        // nothing (B10 in docs/SINOV.md): only a server that accepts counts.
        return canConnect(toUnixSocket: socket)
    }

    static func canConnect(toUnixSocket path: String) -> Bool {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < capacity else { return false }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, length) }
        }
        return result == 0
    }

    private static func backendFile(of bottle: Bottle) -> URL {
        bottle.directory.appending(path: ".active-backend")
    }

    /// The backend whose DLLs were last placed in the bottle.
    public static func activeBackend(of bottle: Bottle) -> GraphicsBackend? {
        (try? String(contentsOf: backendFile(of: bottle), encoding: .utf8))
            .flatMap { GraphicsBackend(rawValue: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func setActiveBackend(_ backend: GraphicsBackend, of bottle: Bottle) {
        try? backend.rawValue.write(to: backendFile(of: bottle), atomically: true, encoding: .utf8)
    }

    /// Windows processes visible on this Mac, as Wine reports them in `ps`:
    /// their command line starts with a Windows path such as `C:\...`.
    public static func windowsProcesses() async -> [WindowsProcess] {
        guard let result = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/bin/ps"), arguments: ["-axo", "pid=,rss=,pcpu=,etime=,command="]
        ) else { return [] }
        return result.stdout.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard fields.count == 5, let pid = Int32(fields[0]) else { return nil }
            let command = String(fields[4])
            let isWindowsPath = command.count > 3 && command.dropFirst().hasPrefix(":\\") && command.first?.isLetter == true
            // Programs Wine was given a Unix path for keep it in their command line.
            let isUnixPathInAPrefix = command.hasPrefix("/") && command.contains("/drive_c/")
                && command.range(of: ".exe", options: .caseInsensitive) != nil
            guard isWindowsPath || isUnixPathInAPrefix else { return nil }
            let path = command.range(of: ".exe", options: .caseInsensitive).map { String(command[..<$0.upperBound]) } ?? command
            let name = path.split(whereSeparator: { $0 == "\\" || $0 == "/" }).last.map(String.init) ?? path
            return WindowsProcess(
                pid: pid,
                name: name,
                path: path,
                residentBytes: (Int64(fields[1]) ?? 0) * 1024,
                cpuPercent: Double(fields[2]) ?? 0,
                elapsed: String(fields[3])
            )
        }
    }

    /// Kills Windows processes of this bottle that no wineserver looks after.
    ///
    /// When a wineserver dies abnormally its clients can linger, some of them
    /// spinning a CPU core (B9 in docs/SINOV.md), and `wineserver -k` from a
    /// new server cannot see them. They are recognised by a working directory
    /// inside the bottle's prefix.
    public static func killOrphans(of bottle: Bottle) async {
        let pids = await windowsProcesses().map(\.pid)
        guard !pids.isEmpty,
              let result = try? await ProcessRunner.run(
                URL(fileURLWithPath: "/usr/sbin/lsof"),
                arguments: ["-a", "-d", "cwd", "-p", pids.map(String.init).joined(separator: ","), "-Fpn"]
              ) else { return }
        let prefix = bottle.prefix.standardizedFileURL.path
        var current: pid_t?
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("p") {
                current = pid_t(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = current, String(line.dropFirst()).hasPrefix(prefix) {
                kill(pid, SIGKILL)
            }
        }
    }

    public static func isProcessRunning(named name: String) async -> Bool {
        await windowsProcesses().contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func waitForProcess(named name: String, toExitWithin timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let alive = await windowsProcesses().contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if !alive { return }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }
}

public struct WindowsProcess: Sendable, Equatable, Identifiable {
    public var pid: Int32
    public var name: String
    public var path: String
    public var residentBytes: Int64
    public var cpuPercent: Double
    public var elapsed: String

    public var id: Int32 { pid }
}

extension Program {
    /// The executable that runs when this program plays, whatever its kind.
    public func mainExecutable(in bottle: Bottle) -> URL? {
        switch kind {
        case .executable:
            executableURL(in: bottle)
        case .steam, .epic:
            Launcher.mainExecutable(ofSteamGameAt: URL(fileURLWithPath: location))
        case .gog:
            storeID.flatMap { GOGStore.launch(installedAt: URL(fileURLWithPath: location), id: $0)?.executable }
                ?? Launcher.mainExecutable(ofSteamGameAt: URL(fileURLWithPath: location))
        }
    }
}
