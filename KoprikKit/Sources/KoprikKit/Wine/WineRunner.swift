import Foundation

/// A running Wine program.
public final class WineProcess: @unchecked Sendable {
    public let logURL: URL
    public let pid: Int32

    private let process: Process
    private let exitTask: Task<Int32, Never>

    fileprivate init(process: Process, logURL: URL, exitTask: Task<Int32, Never>) {
        self.process = process
        self.logURL = logURL
        self.pid = process.processIdentifier
        self.exitTask = exitTask
    }

    public var isRunning: Bool { process.isRunning }

    /// Waits for the launcher process to exit and returns its status.
    ///
    /// With `start /wait` this is when the Windows program ends. Background
    /// helpers such as `wineserver` may outlive it.
    @discardableResult
    public func waitUntilExit() async -> Int32 {
        await exitTask.value
    }

    public func terminate() {
        if process.isRunning { process.terminate() }
    }

    /// Lines appended to the log, delivered as they are written, ending shortly
    /// after the process exits.
    public func outputLines(pollInterval: Duration = .milliseconds(150)) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task { [logURL, process] in
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

                while process.isRunning, !Task.isCancelled {
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

    public init(engine: Engine) {
        self.engine = engine
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
        try log.seekToEnd()
        let header = "\n--- \(Date.now.formatted(.iso8601)) \(executable.lastPathComponent) \(arguments.joined(separator: " "))\n"
        try log.write(contentsOf: Data(header.utf8))

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = log
        process.standardError = log
        process.standardInput = FileHandle.nullDevice

        let (exits, continuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            continuation.yield(finished.terminationStatus)
            continuation.finish()
        }
        let exitTask = Task<Int32, Never> {
            for await status in exits { return status }
            return -1
        }

        do {
            try process.run()
        } catch {
            continuation.finish()
            try? log.close()
            throw error
        }
        // The child has its own copy of the descriptor now.
        try? log.close()
        return WineProcess(process: process, logURL: logURL, exitTask: exitTask)
    }
}
