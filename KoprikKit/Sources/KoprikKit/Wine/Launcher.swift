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
        if (settings.backend ?? .auto) == .auto, isStoreLauncher(target), Graphics.capabilities(of: engine).dxvk {
            return GraphicsDecision(
                backend: .dxvk,
                reason: "Store launchers draw with Chromium, which only renders correctly on DXVK. Games started from the launcher use DXVK too."
            )
        }
        return Graphics.decide(requested: settings.backend, engine: engine, executables: executables(of: target))
    }

    public func launch(
        _ target: LaunchTarget,
        overrides: LaunchSettings = LaunchSettings(),
        wait: Bool = true
    ) async throws -> Launch {
        var settings = resolvedSettings(for: target, overrides: overrides)
        let decision = decide(for: target, settings: settings)
        settings.backend = decision.backend

        let runner = WineRunner(engine: engine)
        var environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: settings)

        // A game started through Steam inherits the Steam client's environment
        // and DLLs. If the client is already up with another backend, it has to
        // be restarted for this game's settings to take effect.
        if case .program(let program) = target, program.kind == .steam,
           BottleActivity.isRunning(bottle), BottleActivity.activeBackend(of: bottle) != decision.backend,
           let steam = SteamLibrary.steamDirectory(in: bottle) {
            let log = bottle.newLogURL(label: "steam-restart")
            _ = try? await runner.run([steam.appending(path: "steam.exe").path, "-shutdown"], environment: environment, logURL: log)
            await BottleActivity.waitForProcess(named: "steam.exe", toExitWithin: .seconds(25))
        }

        if !BottleActivity.isRunning(bottle) || BottleActivity.activeBackend(of: bottle) != decision.backend {
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
            case .steam:
                guard let steam = SteamLibrary.steamDirectory(in: bottle), let appID = program.steamAppID else {
                    throw KoprikError.invalidArgument("Steam is not installed in this bottle.")
                }
                arguments = [steam.appending(path: "steam.exe").path, "-applaunch", String(appID)] + program.arguments
                workingDirectory = steam
            }
        }

        if isSteamClient(target) {
            // Steam's own interface is a Chromium view; async shader compilation keeps it responsive.
            environment["DXVK_ASYNC"] = environment["DXVK_ASYNC"] ?? "1"
        }

        let process = try runner.launch(
            arguments,
            environment: environment,
            workingDirectory: workingDirectory,
            logURL: bottle.newLogURL(label: target.label)
        )
        return Launch(process: process, graphics: decision, settings: settings, environment: environment, arguments: arguments)
    }

    /// Stops everything running in the bottle.
    public func stopAll() async {
        let environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: LaunchSettings())
        // `wineserver -k` exits non-zero when nothing was running, which is fine here.
        _ = try? await WineRunner(engine: engine)
            .wineserver(["-k"], environment: environment, logURL: bottle.newLogURL(label: "kill"))
    }

    // MARK: Helpers

    /// Executables of launchers whose interface is a Chromium view.
    private static let storeLauncherNames: Set<String> = [
        "steam.exe", "steamwebhelper.exe", "epicgameslauncher.exe", "galaxyclient.exe", "battle.net.exe",
        "battle.net launcher.exe", "eadesktop.exe", "ealauncher.exe", "ubisoftconnect.exe", "upc.exe",
    ]

    private func isStoreLauncher(_ target: LaunchTarget) -> Bool {
        let path: String
        switch target {
        case .program(let program):
            if program.kind == .steam { return true }
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
            case .steam:
                return Self.gameExecutables(in: URL(fileURLWithPath: program.location))
            }
        }
    }

    /// The larger executables in a game folder, a few levels deep. Small files
    /// are skipped: they are crash reporters, redistributable installers and
    /// the like, and would only blur the picture.
    public static func gameExecutables(in folder: URL, limit: Int = 12) -> [URL] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
        ) else { return [] }
        var found: [(url: URL, size: Int)] = []
        for case let url as URL in enumerator {
            if enumerator.level > 4 { enumerator.skipDescendants(); continue }
            guard url.pathExtension.lowercased() == "exe",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let size = values.fileSize, size > 512 * 1024 else { continue }
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
              let device = attributes[.systemNumber] as? UInt64 ?? (attributes[.systemNumber] as? Int).map(UInt64.init),
              let inode = attributes[.systemFileNumber] as? UInt64 ?? (attributes[.systemFileNumber] as? Int).map(UInt64.init)
        else { return false }
        let socket = "/tmp/.wine-\(getuid())/server-\(String(device, radix: 16))-\(String(inode, radix: 16))/socket"
        return FileManager.default.fileExists(atPath: socket)
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
            guard command.count > 3, command.dropFirst().hasPrefix(":\\"), command.first?.isLetter == true else { return nil }
            let path = command.range(of: ".exe", options: .caseInsensitive).map { String(command[..<$0.upperBound]) } ?? command
            return WindowsProcess(
                pid: pid,
                name: path.split(separator: "\\").last.map(String.init) ?? path,
                path: path,
                residentBytes: (Int64(fields[1]) ?? 0) * 1024,
                cpuPercent: Double(fields[2]) ?? 0,
                elapsed: String(fields[3])
            )
        }
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
