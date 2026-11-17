import Darwin
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
        // posix_spawn and waitpid rather than Foundation's Process: its
        // waitUntilExit spins the calling thread's run loop and was seen to
        // never return inside the long-running command-line tool.
        var outputPipe: [Int32] = [0, 0]
        var errorPipe: [Int32] = [0, 0]
        guard pipe(&outputPipe) == 0, pipe(&errorPipe) == 0 else {
            throw KoprikError.commandFailed(command: executable.lastPathComponent, status: errno, output: "pipe failed")
        }

        var attributes = posix_spawnattr_t(nil as OpaquePointer?)
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var actions = posix_spawn_file_actions_t(nil as OpaquePointer?)
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, outputPipe[1], 1)
        posix_spawn_file_actions_adddup2(&actions, errorPipe[1], 2)
        if let currentDirectory {
            posix_spawn_file_actions_addchdir_np(&actions, currentDirectory.path)
        }

        let variables = environment ?? ProcessInfo.processInfo.environment
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = variables.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }

        var pid: pid_t = 0
        let spawned = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        close(outputPipe[1])
        close(errorPipe[1])
        guard spawned == 0 else {
            close(outputPipe[0])
            close(errorPipe[0])
            throw KoprikError.commandFailed(
                command: executable.lastPathComponent, status: spawned, output: String(cString: strerror(spawned))
            )
        }

        // Each blocking read and the wait get a thread of their own, off the cooperative pool.
        let (outputReader, errorReader, child) = (outputPipe[0], errorPipe[0], pid)
        async let out = blocking { readAll(from: outputReader) }
        async let err = blocking { readAll(from: errorReader) }
        async let status = blocking { () -> Int32 in
            var raw: Int32 = 0
            while waitpid(child, &raw, 0) == -1 && errno == EINTR {}
            return WineProcess.exitStatus(fromWaitStatus: raw)
        }
        let (output, errors, code) = await (out, err, status)

        return ProcessResult(
            status: code,
            stdout: String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines),
            stderr: String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private static func readAll(from descriptor: Int32) -> Data {
        defer { close(descriptor) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(buffer, count: count)
            } else if count == 0 || errno != EINTR {
                return data
            }
        }
    }

    private static func blocking<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: work()) }
        }
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

}
