import Foundation

public struct ProcessResult: Sendable, Equatable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { status == 0 }
    public var combinedOutput: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Runs short-lived helper tools (`tar`, `xattr`, `arch`, `wine --version`) and
/// captures their output.
///
/// Do not use this for Wine programs: `wineserver` and other children inherit
/// the pipes and keep them open long after the launcher exits, so reading to
/// end-of-file would hang. `WineRunner` writes to a log file instead.
public enum ProcessRunner {
    public static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Drain both pipes concurrently so a chatty tool cannot fill one and block.
        async let stdoutData = readToEnd(stdoutPipe.fileHandleForReading)
        async let stderrData = readToEnd(stderrPipe.fileHandleForReading)
        let (out, err) = await (stdoutData, stderrData)
        process.waitUntilExit()

        return ProcessResult(
            status: process.terminationStatus,
            stdout: String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Runs a tool and throws `KoprikError.commandFailed` unless it exits with 0.
    @discardableResult
    public static func runChecked(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil
    ) async throws -> ProcessResult {
        let result = try await run(
            executable, arguments: arguments, environment: environment, currentDirectory: currentDirectory
        )
        guard result.succeeded else {
            throw KoprikError.commandFailed(
                command: ([executable.lastPathComponent] + arguments).joined(separator: " "),
                status: result.status,
                output: result.combinedOutput
            )
        }
        return result
    }

    private static func readToEnd(_ handle: FileHandle) async -> Data {
        await Task.detached { (try? handle.readToEnd()) ?? Data() }.value
    }
}
