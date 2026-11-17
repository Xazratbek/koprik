import ArgumentParser
import Foundation
import KoprikKit

@main
struct Koprik: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "koprik",
        abstract: "Run Windows programs on macOS through Wine.",
        subcommands: [Doctor.self, EngineCommand.self, BottleCommand.self, Run.self, Stop.self, Programs.self, Processes.self, Kill.self, Env.self, Links.self]
    )
}

// MARK: - doctor

struct Doctor: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Check that this Mac is ready to run Wine.")

    func run() async throws {
        let paths = AppPaths.default
        print("Data folder: \(paths.root.path)")

        let rosetta = await Rosetta.isAvailable()
        print("Rosetta 2:   \(rosetta ? "available" : "MISSING (softwareupdate --install-rosetta --agree-to-license)")")

        let engines = try await EngineStore(paths: paths).installed()
        if engines.isEmpty {
            print("Engines:     none (koprik engine install gaming)")
        } else {
            for engine in engines {
                let version = engine.manifest.wineVersion ?? "version unknown"
                let d3dmetal = engine.manifest.d3dmetalCapable ? ", D3DMetal-capable" : ""
                print("Engine:      \(engine.id) (\(version)\(d3dmetal))")
            }
        }

        let bottles = try await BottleStore(paths: paths).all()
        print("Bottles:     \(bottles.isEmpty ? "none" : bottles.map(\.name).joined(separator: ", "))")
        if !rosetta { throw ExitCode.failure }
    }
}

// MARK: - engine

struct EngineCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "engine",
        abstract: "Manage Wine builds.",
        subcommands: [List.self, Install.self, Import.self, Remove.self, GameMode.self, ImportGPTK.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show installed engines.")

        func run() async throws {
            let engines = try await EngineStore().installed()
            if engines.isEmpty { print("No engines installed. Try: koprik engine install gaming") }
            for engine in engines {
                let parts = engine.manifest.components.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }
                print("\(engine.id)\n  \(engine.name)")
                print("  wine: \(engine.manifest.wineVersion ?? "unknown")  d3dmetal-capable: \(engine.manifest.d3dmetalCapable)")
                if !parts.isEmpty { print("  bundled: \(parts.joined(separator: ", "))") }
            }
        }
    }

    struct Install: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Download and install an engine.",
            discussion: """
            SOURCE is one of:
              gaming   Wine with CrossOver's patches (frankea/winecx-gptk). Needed for D3DMetal. About 480 MB.
              plain    Upstream Wine (Gcenx build).
              koprik   Ko'prik's own build of the same sources (scripts/build-engine.sh).
            """
        )

        @Argument(help: "gaming or plain.") var source: String
        @Option(help: "Release tag to install instead of the recommended one.") var tag: String?
        @Option(help: "Gcenx channel for 'plain': stable, devel or staging.") var channel: GcenxChannel = .devel

        func run() async throws {
            let engineSource: EngineSource
            switch source.lowercased() {
            case "gaming":
                engineSource = tag.map { .winecxGPTK(tag: $0) } ?? .recommendedGaming
            case "plain":
                engineSource = tag.map { .gcenx(channel: channel, tag: $0) } ?? .recommendedPlain
            case "koprik":
                engineSource = .koprik(tag: tag ?? "engine-v0.1.0")
            default:
                throw ValidationError("Unknown source \"\(source)\". Use gaming, plain or koprik.")
            }

            print("Installing \(engineSource.displayName)")
            if engineSource.pinnedSHA256 == nil && engineSource.checksumURL == nil {
                print("Note: this release publishes no checksum, so the download cannot be verified.")
            }
            let reporter = ProgressReporter()
            let engine = try await EngineStore().install(engineSource) { reporter.report($0) }
            print("\nInstalled \(engine.id) (\(engine.manifest.wineVersion ?? "could not run wine --version"))")
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Install an engine from a folder or tar archive on disk.")

        @Argument(help: "Path to a Wine tree or archive.") var path: String
        @Option(help: "Identifier for the engine.") var id: String?
        @Option(help: "Display name.") var name: String?

        func run() async throws {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let engine = try await EngineStore().importLocal(at: url, id: id, name: name)
            print("Imported \(engine.id) (\(engine.manifest.wineVersion ?? "version unknown"))")
        }
    }

    struct ImportGPTK: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "import-gptk",
            abstract: "Install Apple's Game Porting Toolkit (D3DMetal) into an engine, for DirectX 12 games."
        )

        @Argument(help: "The toolkit's .dmg or a folder containing its redist/lib.") var path: String
        @Option(help: "Engine id. Defaults to the newest D3DMetal-capable engine.") var engine: String?

        func run() async throws {
            let store = EngineStore()
            let target: Engine
            if let engine {
                target = try await store.engine(id: engine)
            } else if let preferred = try await store.preferred(), preferred.manifest.d3dmetalCapable {
                target = preferred
            } else {
                throw ValidationError("No D3DMetal-capable engine installed. Run: koprik engine install gaming")
            }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            let version = try await GPTKImporter.importToolkit(from: url, into: target)
            print("Imported D3DMetal \(version ?? "(version unknown)") into \(target.id)")
        }
    }

    struct GameMode: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "game-mode",
            abstract: "Build the app bundle that lets macOS give Windows games Game Mode."
        )

        @Argument(help: "Engine id. Defaults to every installed engine.") var id: String?
        @Flag(help: "Remove the bundle instead.") var remove = false

        func run() async throws {
            let store = EngineStore()
            let engines: [Engine]
            if let id {
                engines = [try await store.engine(id: id)]
            } else {
                engines = try await store.installed()
            }
            for engine in engines {
                if remove {
                    await GameBundle.remove(from: engine)
                    print("Removed the Game Mode bundle from \(engine.id)")
                } else {
                    let bundle = try await GameBundle.build(for: engine)
                    print("\(engine.id): \(bundle.path)")
                }
            }
        }
    }

    struct Remove: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete an installed engine.")

        @Argument var id: String

        func run() async throws {
            let users = try await BottleStore().all().filter { $0.config.engineID == id }
            guard users.isEmpty else {
                throw KoprikError.invalidArgument("Engine \(id) is still used by: \(users.map(\.name).joined(separator: ", ")).")
            }
            try await EngineStore().remove(id: id)
            print("Removed \(id)")
        }
    }
}

extension GcenxChannel: ExpressibleByArgument {}
extension WindowsVersion: ExpressibleByArgument {}
extension GraphicsBackend: ExpressibleByArgument {}
extension SyncMode: ExpressibleByArgument {}
extension DXVKHud: ExpressibleByArgument {}
extension Isolation: ExpressibleByArgument {}

// MARK: - bottle

struct BottleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bottle",
        abstract: "Manage bottles (isolated Windows environments).",
        subcommands: [List.self, Create.self, Delete.self, Rename.self, Duplicate.self,
                      Snapshot.self, Snapshots.self, Restore.self]
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show all bottles.")

        func run() async throws {
            let bottles = try await BottleStore().all()
            if bottles.isEmpty { print("No bottles. Try: koprik bottle create <name>") }
            for bottle in bottles {
                print("\(bottle.name)  [\(bottle.config.windowsVersion.displayName), engine \(bottle.config.engineID)]")
                print("  \(bottle.directory.path)")
            }
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a bottle.")

        @Argument var name: String
        @Option(help: "Engine id. Defaults to the newest D3DMetal-capable engine.") var engine: String?
        @Option(name: .customLong("windows"), help: "win7, win8, win81, win10 or win11.") var windowsVersion: WindowsVersion = .win10
        @Option(help: "off, files (no access to your files or Mac programs) or full (also no internet).") var isolation: Isolation = .off

        func run() async throws {
            guard await Rosetta.isAvailable() else { throw KoprikError.rosettaMissing }
            let engines = EngineStore()
            let chosen: Engine
            if let engine {
                chosen = try await engines.engine(id: engine)
            } else if let preferred = try await engines.preferred() {
                chosen = preferred
            } else {
                throw ValidationError("No engine installed. Run: koprik engine install gaming")
            }
            print("Creating \"\(name)\" on \(chosen.id) (this takes up to a minute)...")
            let store = BottleStore()
            var bottle = try await store.create(name: name, engine: chosen, windowsVersion: windowsVersion)
            if isolation.isOn {
                bottle.config.isolation = isolation
                bottle = try await store.save(bottle)
            }
            print("Created \(bottle.name) at \(bottle.directory.path)")
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Move a bottle to the Trash.")

        @Argument var name: String
        @Flag(help: "Delete immediately instead of moving to the Trash.") var permanently = false

        func run() async throws {
            let store = BottleStore()
            let bottle = try await store.bottle(name)
            try await stopEverything(in: bottle)
            try await store.delete(bottle, permanently: permanently)
            print(permanently ? "Deleted \(bottle.name)" : "Moved \(bottle.name) to the Trash")
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a bottle.")

        @Argument var name: String
        @Argument var newName: String

        func run() async throws {
            let store = BottleStore()
            let renamed = try await store.rename(try await store.bottle(name), to: newName)
            print("Renamed to \(renamed.name)")
        }
    }

    struct Duplicate: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy a bottle under a new name.")

        @Argument var name: String
        @Argument var newName: String

        func run() async throws {
            let store = BottleStore()
            let bottle = try await store.bottle(name)
            try await stopEverything(in: bottle)
            let copy = try await store.duplicate(bottle, as: newName)
            print("Created \(copy.name) at \(copy.directory.path)")
        }
    }

    struct Snapshot: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save the bottle's current state.")

        @Argument var name: String
        @Option(help: "A note to recognise the snapshot by.") var label = "manual"

        func run() async throws {
            let store = BottleStore()
            let bottle = try await store.bottle(name)
            try await stopEverything(in: bottle)
            let snapshot = try await store.snapshot(bottle, label: label)
            print("Saved snapshot \(snapshot.id) (\(snapshot.label))")
        }
    }

    struct Snapshots: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List a bottle's snapshots.")

        @Argument var name: String

        func run() async throws {
            let store = BottleStore()
            let snapshots = try await store.snapshots(of: try await store.bottle(name))
            if snapshots.isEmpty { print("No snapshots.") }
            for snapshot in snapshots {
                print("\(snapshot.id)  \(snapshot.createdAt.formatted(date: .abbreviated, time: .shortened))  \(snapshot.label)")
            }
        }
    }

    struct Restore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Roll a bottle back to a snapshot.")

        @Argument var name: String
        @Argument(help: "Snapshot id from 'koprik bottle snapshots'.") var snapshot: String

        func run() async throws {
            let store = BottleStore()
            let bottle = try await store.bottle(name)
            try await stopEverything(in: bottle)
            try await store.restore(bottle, snapshotID: snapshot)
            print("Restored \(bottle.name) to \(snapshot)")
        }
    }
}

// MARK: - run / kill / env

struct LaunchOptions: ParsableArguments {
    @Option(help: "Graphics backend: auto, d3dmetal, dxmt, dxvk or wined3d.") var backend: GraphicsBackend?
    @Option(help: "Synchronisation: none, esync or msync.") var sync: SyncMode?
    @Flag(help: "Show Apple's Metal performance HUD.") var metalHud = false
    @Option(help: "DXVK HUD: off, fps, partial or full.") var dxvkHud: DXVKHud?
    @Flag(help: "Advertise AVX support under Rosetta.") var avx = false
    @Flag(help: "Enable DirectX Raytracing in D3DMetal.") var raytracing = false
    @Option(name: .customLong("env"), help: "Extra environment variable as KEY=VALUE. Repeatable.") var environment: [String] = []

    func settings() throws -> LaunchSettings {
        var variables: [String: String] = [:]
        for pair in environment {
            guard let separator = pair.firstIndex(of: "="), separator != pair.startIndex else {
                throw ValidationError("--env expects KEY=VALUE, got \"\(pair)\".")
            }
            variables[String(pair[..<separator])] = String(pair[pair.index(after: separator)...])
        }
        return LaunchSettings(
            backend: backend,
            sync: sync,
            metalHUD: metalHud ? true : nil,
            dxvkHUD: dxvkHud,
            advertiseAVX: avx ? true : nil,
            raytracing: raytracing ? true : nil,
            environment: variables.isEmpty ? nil : variables
        )
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run a Windows program in a bottle.",
        discussion: """
        TARGET is either a file on this Mac (.exe, .msi, .lnk) or the name of a
        program inside the bottle, such as notepad, winecfg, regedit or taskmgr.
        """
    )

    @Argument(help: "Bottle name.") var bottle: String
    @Argument(help: "File path or program name.") var target: String
    @Argument(help: "Arguments passed to the program. Put -- before any that start with a dash.") var arguments: [String] = []
    @OptionGroup var launch: LaunchOptions
    @Flag(help: "Return immediately instead of waiting for the program to exit.") var detach = false
    @Flag(help: "Print Wine's output while the program runs.") var verbose = false

    func run() async throws {
        guard await Rosetta.isAvailable() else { throw KoprikError.rosettaMissing }
        let (bottle, engine) = try await resolve(bottleNamed: bottle)
        let launcher = Launcher(bottle: bottle, engine: engine)

        let file = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
        let launchTarget: LaunchTarget
        if FileManager.default.fileExists(atPath: file.path) {
            launchTarget = .file(file, arguments: arguments)
        } else if let program = await ProgramStore().programs(in: bottle, includeHidden: true).first(where: {
            $0.id == target || $0.name.compare(target, options: .caseInsensitive) == .orderedSame
        }) {
            var chosen = program
            chosen.arguments += arguments
            launchTarget = .program(chosen)
        } else {
            launchTarget = .command(target, arguments: arguments)
        }

        let started = Date.now
        let launch = try await launcher.launch(launchTarget, overrides: try self.launch.settings(), wait: !detach)
        let note = "Log: \(launch.process.logURL.path)\nGraphics: \(launch.graphics.backend.displayName). \(launch.graphics.reason)\n"
        FileHandle.standardError.write(Data(note.utf8))
        if detach { return }

        if verbose {
            for await line in launch.process.outputLines() { print(line) }
        }
        let status = await launch.process.waitUntilExit()
        if case .program(let program) = launchTarget {
            _ = try? await ProgramStore().recordSession(
                programID: program.id, in: bottle, started: started, duration: Date.now.timeIntervalSince(started)
            )
        }
        if status != 0 { throw ExitCode(status) }
    }
}

struct Programs: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the programs found in a bottle.")

    @Argument(help: "Bottle name.") var bottle: String

    func run() async throws {
        let (bottle, engine) = try await resolve(bottleNamed: bottle)
        let launcher = Launcher(bottle: bottle, engine: engine)
        let programs = await ProgramStore().programs(in: bottle)
        if programs.isEmpty { print("No programs found. Install something, or run a file with: koprik run \(bottle.name) <file>") }
        for program in programs {
            let decision = launcher.graphicsDecision(for: .program(program))
            print("\(program.name)  [\(program.id), \(decision.backend.displayName)]")
            print("  \(program.location)")
        }
    }
}

struct Processes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ps", abstract: "List running Windows processes.")

    func run() async throws {
        let processes = await BottleActivity.windowsProcesses()
        if processes.isEmpty { print("Nothing is running.") }
        for process in processes {
            let memory = String(format: "%.0f MB", Double(process.residentBytes) / 1_048_576)
            print("\(process.pid)\t\(process.cpuPercent)%\t\(memory)\t\(process.elapsed)\t\(process.name)")
        }
    }
}

struct Stop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Close one program and leave the rest of the bottle running.",
        discussion: "PROGRAM is a name from 'koprik programs' or an executable name such as game.exe."
    )

    @Argument var bottle: String
    @Argument var program: String

    func run() async throws {
        let (bottle, engine) = try await resolve(bottleNamed: bottle)
        var executable = program
        if let match = await ProgramStore().programs(in: bottle, includeHidden: true)
            .first(where: { $0.name.compare(program, options: .caseInsensitive) == .orderedSame }) {
            executable = match.mainExecutable(in: bottle)?.lastPathComponent ?? program
        }
        await Launcher(bottle: bottle, engine: engine).stop(programNamed: executable)
        let stillRunning = await BottleActivity.isProcessRunning(named: executable)
        print(stillRunning ? "\(executable) is still running" : "Closed \(executable)")
        if stillRunning { throw ExitCode.failure }
    }
}

struct Links: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Make links that Windows programs registered (notion://, zoommtg://) open them from the Mac."
    )

    @Argument var bottle: String

    func run() async throws {
        let (bottle, _) = try await resolve(bottleNamed: bottle)
        let schemes = try await LinkBridge.update(for: bottle)
        print(schemes.isEmpty ? "No links registered in \(bottle.name)." : "\(bottle.name) now handles: \(schemes.map { $0 + "://" }.joined(separator: ", "))")
    }
}

struct Kill: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Stop every program running in a bottle.")

    @Argument var bottle: String

    func run() async throws {
        let (bottle, _) = try await resolve(bottleNamed: bottle)
        try await stopEverything(in: bottle)
        print("Stopped everything in \(bottle.name)")
    }
}

struct Env: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Print shell exports for working in a bottle by hand.",
        discussion: "Use as: eval \"$(koprik env <bottle>)\" and then run wine directly."
    )

    @Argument var bottle: String
    @OptionGroup var launch: LaunchOptions

    func run() async throws {
        let (bottle, engine) = try await resolve(bottleNamed: bottle)
        let settings = LaunchSettings.resolve([engine.defaultSettings, bottle.config.settings, try launch.settings()])
        let host = ProcessInfo.processInfo.environment
        let environment = WineEnvironment.build(engine: engine, prefix: bottle.prefix, settings: settings, host: host)
        // Only what Ko'prik adds or changes; the rest is already in the caller's shell.
        let changed = Set(environment.filter { host[$0.key] != $0.value }.keys)
        print(WineEnvironment.shellExports(environment, onlyKeys: changed))
    }
}

// MARK: - shared helpers

func resolve(bottleNamed name: String) async throws -> (Bottle, Engine) {
    let bottle = try await BottleStore().bottle(name)
    let engine = try await EngineStore().engine(id: bottle.config.engineID)
    return (bottle, engine)
}

/// Kills the bottle's wineserver so that its files can be copied or replaced safely.
func stopEverything(in bottle: Bottle) async throws {
    guard let engine = try? await EngineStore().engine(id: bottle.config.engineID) else { return }
    await Launcher(bottle: bottle, engine: engine).stopAll()
}

/// Prints download progress on one line, at most a few times per second.
final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPrinted = Date.distantPast

    func report(_ progress: DownloadProgress) {
        let shouldPrint = lock.withLock {
            let now = Date.now
            guard now.timeIntervalSince(lastPrinted) > 0.25 || progress.fraction == 1 else { return false }
            lastPrinted = now
            return true
        }
        guard shouldPrint else { return }
        let megabytes = { (bytes: Int64) in String(format: "%.0f MB", Double(bytes) / 1_048_576) }
        let text = if let fraction = progress.fraction, let total = progress.totalBytes {
            String(format: "\r  %3.0f%%  %@ of %@   ", fraction * 100, megabytes(progress.receivedBytes), megabytes(total))
        } else {
            "\r  \(megabytes(progress.receivedBytes))   "
        }
        FileHandle.standardError.write(Data(text.utf8))
    }
}
