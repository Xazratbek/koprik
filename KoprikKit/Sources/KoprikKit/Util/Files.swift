import CryptoKit
import Foundation

enum JSONFile {
    static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }

    /// Writes `value` and returns it exactly as it will be read back.
    ///
    /// Dates are stored as ISO 8601 without fractional seconds, so the stored
    /// record differs slightly from the one in memory. Callers that hand the
    /// record on should use the returned value, so that what they hold always
    /// equals what a later read produces.
    @discardableResult
    static func write<Value: Codable>(_ value: Value, to url: URL) throws -> Value {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Value.self, from: data)
    }
}

public enum Checksum {
    /// SHA-256 of a file as lowercase hex, read in chunks so large archives stay out of memory.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Reads the hash out of a `shasum`-style line: `<hex>  <filename>`.
    public static func parseShasumFile(_ text: String) -> String? {
        let token = text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased()
        guard let token, token.count == 64, token.allSatisfy(\.isHexDigit) else { return nil }
        return token
    }
}

public enum Archive {
    /// Extracts a tar archive (gzip, xz, zstd or plain; bsdtar detects the format).
    public static func extract(_ archive: URL, to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try await ProcessRunner.runChecked(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-xf", archive.path, "-C", directory.path]
        )
    }

    /// Removes the Gatekeeper quarantine flag so downloaded Wine binaries may run.
    /// A missing attribute is not an error, so failures are ignored.
    public static func removeQuarantine(at url: URL) async {
        _ = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/xattr"),
            arguments: ["-dr", "com.apple.quarantine", url.path]
        )
    }
}

public enum Rosetta {
    /// Whether x86_64 binaries can run on this Mac. Every public Wine build for
    /// macOS is x86_64, so nothing works without it.
    public static func isAvailable() async -> Bool {
        let result = try? await ProcessRunner.run(
            URL(fileURLWithPath: "/usr/bin/arch"),
            arguments: ["-x86_64", "/usr/bin/true"]
        )
        return result?.succeeded ?? false
    }
}
