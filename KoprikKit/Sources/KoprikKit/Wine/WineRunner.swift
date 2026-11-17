import Darwin
import Foundation

/// A running Wine program.
public final class WineProcess: @unchecked Sendable {
    public let logURL: URL
    public let pid: pid_t

    private let exitTask: Task<Int32, Never>
    private let lock = NSLock()
    private var exited = false

    fileprivate init(pid: pid_t, logURL: URL) {
        self.pid = pid
        self.logURL = logURL
        let (statuses, continuation) = AsyncStream<Int32>.makeStream()
        exitTask = Task<Int32, Never> {
            for await status in statuses { return status }
            return -1
        }
        // waitpid blocks, so it gets a thread of its own rather than one of
        // the cooperative pool's.
        Thread.detachNewThread { [weak self] in
            var raw: Int32 = 0
            while waitpid(pid, &raw, 0) == -1 && errno == EINTR {}
            self?.markExited()
            continuation.yield(Self.exitStatus(fromWaitStatus: raw))
            continuation.finish()
        }
    }

    private func markExited() {
        lock.withLock { exited = true }
    }

    /// Decodes a `waitpid` status: the exit code, or 128 + signal number.
    static func exitStatus(fromWaitStatus raw: Int32) -> Int32 {
        let signal = raw & 0x7F
        return signal == 0 ? (raw >> 8) & 0xFF : 128 + signal
    }

    public var isRunning: Bool { lock.withLock { !exited } }

    /// Waits for the launcher process to exit and returns its status.
    ///
    /// With `start /wait` this is when the Windows program ends. Background
    /// helpers such as `wineserver` may outlive it.
    @discardableResult
    public func waitUntilExit() async -> Int32 {
        await exitTask.value
    }

    public func terminate() {
        if isRunning { kill(pid, SIGTERM) }
    }

    /// Lines appended to the log, delivered as they are written, ending shortly
    /// after the process exits.
    public func outputLines(pollInterval: Duration = .milliseconds(150)) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task { [logURL, weak self] in
                guard let handle = try? FileHandle(forReadingFrom: logURL) else {
                    continuation.finish()
                    return
                }
                defer { try? handle.close() }
                var pending = ""

                func drain() {
                    guard let data = try? handle.readToEnd(), !data.isEmpty else { return }
                    pending += String(decoding: data, as: UTF8.self)
                    while let newline = pending.firstIndex(of: "\n") {
                        continuation.yield(String(pending[..<newline]))
                        pending = String(pending[pending.index(after: newline)...])
                    }
                }

                while self?.isRunning == true, !Task.isCancelled {
                    drain()
                    try? await Task.sleep(for: pollInterval)
                }
                drain()
                if !pending.isEmpty { continuation.yield(pending) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Starts Wine from a particular engine.
public struct WineRunner: Sendable {
    public let engine: Engine
    /// A Seatbelt profile; when set, every process starts inside it (see Isolation).
    public let sandboxProfile: String?

    public init(engine: Engine, sandboxProfile: String? = nil) {
        self.engine = engine
        self.sandboxProfile = sandboxProfile
    }

    /// Starts `wine <arguments>` and returns immediately.
    ///
    /// Output goes to `logURL` rather than a pipe: `wineserver` inherits the
    /// descriptors and would keep a pipe open long after the program exits.
    public func launch(
        _ arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        logURL: URL
    ) throws -> WineProcess {
        try start(engine.wineBinary, arguments: arguments, environment: environment,
                  workingDirectory: workingDirectory, logURL: logURL)
    }

    /// Runs `wine <arguments>` to completion and returns the exit status.
    @discardableResult
    public func run(
        _ arguments: [String],
        environment: [String: String],
        workingDirectory: URL? = nil,
        logURL: URL
    ) async throws -> Int32 {
        try await launch(arguments, environment: environment, workingDirectory: workingDirectory, logURL: logURL)
            .waitUntilExit()
    }

    /// Runs `wineserver` with the given flags: `-w` waits for the prefix to go
    /// idle, `-k` kills everything running in it.
    @discardableResult
    public func wineserver(_ arguments: [String], environment: [String: String], logURL: URL) async throws -> Int32 {
        try await start(engine.wineserverBinary, arguments: arguments, environment: environment,
                        workingDirectory: nil, logURL: logURL)
            .waitUntilExit()
    }

    /// Arguments that open a file from the Mac file system in Wine.
    ///
    /// `start /unix` accepts a Unix path and applies Windows file associations,
    /// so the same call handles `.exe`, `.msi` and `.lnk`. `/wait` keeps the
    /// launcher alive until the program ends.
    public static func startArguments(for file: URL, programArguments: [String] = [], wait: Bool = true) -> [String] {
        ["start"] + (wait ? ["/wait"] : []) + ["/unix", file.path] + programArguments
    }

    /// Spawns the process in a session of its own.
    ///
    /// `wineserver` and every Windows program descend from the first Wine
    /// process. Left in the caller's session, they would all be killed when
    /// the terminal that ran `koprik run` closes, or when a tool that started
    /// it cleans up its process group. Steam was lost this way during testing.
    private func start(
        _ executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?,
        logURL: URL
    ) throws -> WineProcess {
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: executable.path) else {
            throw KoprikError.wineBinaryNotFound(engine.wineRoot)
        }
        try manager.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !manager.fileExists(atPath: logURL.path) {
            manager.createFile(atPath: logURL.path, contents: nil)
        }
        let log = try FileHandle(forWritingTo: logURL)
        defer { try? log.close() }
        try log.seekToEnd()
        let header = "\n--- \(Date.now.formatted(.iso8601)) \(executable.lastPathComponent) \(arguments.joined(separator: " "))\n"
        try log.write(contentsOf: Data(header.utf8))

        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, log.fileDescriptor, 1)
        posix_spawn_file_actions_adddup2(&actions, log.fileDescriptor, 2)
        if let workingDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, workingDirectory.path)
        }

        // In an isolated bottle the process starts inside the sandbox, and so does everything it starts.
        var program = executable
        var commandLine = [executable.path] + arguments
        if let sandboxProfile {
            program = Sandbox.executable
            commandLine = [Sandbox.executable.path, "-p", sandboxProfile, executable.path] + arguments
        }
        let argv = commandLine.map { strdup($0) } + [nil]
        let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, program.path, &actions, &attributes, argv, envp)
        guard result == 0 else {
            throw KoprikError.commandFailed(
                command: executable.lastPathComponent, status: result,
                output: String(cString: strerror(result))
            )
        }
        return WineProcess(pid: pid, logURL: logURL)
    }
}
