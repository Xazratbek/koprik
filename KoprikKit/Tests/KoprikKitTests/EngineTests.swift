import Foundation
import Testing
@testable import KoprikKit

@Suite struct EngineSourceTests {
    @Test func winecxURLsFollowTheReleaseLayout() {
        let source = EngineSource.winecxGPTK(tag: "runtime-v4.8.3")
        #expect(source.archiveURL?.absoluteString
            == "https://github.com/frankea/winecx-gptk/releases/download/runtime-v4.8.3/Libraries.tar.gz")
        #expect(source.checksumURL?.absoluteString
            == "https://github.com/frankea/winecx-gptk/releases/download/runtime-v4.8.3/Libraries.tar.gz.sha256")
        #expect(source.defaultID == "winecx-gptk-4.8.3")
        #expect(source.d3dmetalCapable)
        #expect(source.pinnedSHA256?.count == 64)
    }

    @Test func gcenxURLsFollowTheReleaseLayout() {
        let source = EngineSource.gcenx(channel: .staging, tag: "11.21")
        #expect(source.archiveURL?.absoluteString
            == "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.21/wine-staging-11.21-osx64.tar.xz")
        #expect(source.checksumURL == nil)
        #expect(source.defaultID == "wine-staging-11.21")
        #expect(!source.d3dmetalCapable)
    }

    @Test func unreviewedReleasesHaveNoPinnedHash() {
        #expect(EngineSource.winecxGPTK(tag: "runtime-v9.9.9").pinnedSHA256 == nil)
    }

    @Test func surviveAJSONRoundTrip() throws {
        for source in [EngineSource.recommendedGaming, .recommendedPlain, .local(path: "/tmp/My Wine")] {
            let decoded = try JSONDecoder().decode(EngineSource.self, from: JSONEncoder().encode(source))
            #expect(decoded == source)
        }
    }
}

@Suite struct ChecksumTests {
    @Test func hashesAFile() throws {
        let scratch = try Scratch()
        let file = scratch.root.appending(path: "abc.txt")
        try Data("abc".utf8).write(to: file)
        #expect(try Checksum.sha256(of: file) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func parsesShasumLinesAndRejectsGarbage() {
        let hash = String(repeating: "aB", count: 32)
        #expect(Checksum.parseShasumFile("\(hash)  Libraries.tar.gz\n") == hash.lowercased())
        #expect(Checksum.parseShasumFile("not a hash") == nil)
        #expect(Checksum.parseShasumFile("<html>404</html>") == nil)
        #expect(Checksum.parseShasumFile("") == nil)
    }
}

@Suite struct EngineStoreTests {
    @Test func importsAFolderAndRecordsItsVersion() async throws {
        let scratch = try Scratch()
        let store = EngineStore(paths: scratch.paths)
        let engine = try await store.importLocal(at: try scratch.makeFakeWineTree(), id: "fake", name: "Fake")

        #expect(engine.id == "fake")
        #expect(engine.manifest.wineVersion == "wine-11.19 (fake)")
        #expect(engine.manifest.wineRoot == "")
        #expect(FileManager.default.isExecutableFile(atPath: engine.wineBinary.path))
        #expect(try await store.installed().map(\.id) == ["fake"])
        #expect(try await store.engine(id: "fake").manifest == engine.manifest)
    }

    @Test func findsWineNestedInsideAnArchive() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeFakeWineTree(named: "Libraries", nestedUnder: "Wine")
        let archive = scratch.root.appending(path: "Libraries.tar.gz")
        try await ProcessRunner.runChecked(
            URL(fileURLWithPath: "/usr/bin/tar"),
            arguments: ["-czf", archive.path, "-C", scratch.root.path, tree.lastPathComponent]
        )

        let engine = try await EngineStore(paths: scratch.paths).importLocal(at: archive, id: "nested")
        #expect(engine.manifest.wineRoot == "Libraries/Wine")
        #expect(engine.wineBinary.path.hasSuffix("Engines/nested/Libraries/Wine/bin/wine64"))
        #expect(engine.manifest.wineVersion == "wine-11.19 (fake)")
    }

    @Test func rejectsATreeWithoutWineAndLeavesNothingBehind() async throws {
        let scratch = try Scratch()
        let empty = scratch.root.appending(path: "empty", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        let store = EngineStore(paths: scratch.paths)

        await #expect(throws: KoprikError.self) {
            try await store.importLocal(at: empty, id: "broken")
        }
        #expect(try await store.installed().isEmpty)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: scratch.paths.engines.path)
        #expect(leftovers.isEmpty)
    }

    @Test func refusesToInstallTheSameIDTwice() async throws {
        let scratch = try Scratch()
        let store = EngineStore(paths: scratch.paths)
        let tree = try scratch.makeFakeWineTree()
        _ = try await store.importLocal(at: tree, id: "fake")
        await #expect(throws: KoprikError.engineAlreadyInstalled("fake")) {
            try await store.importLocal(at: tree, id: "fake")
        }
    }

    @Test func removesAnEngine() async throws {
        let scratch = try Scratch()
        let store = EngineStore(paths: scratch.paths)
        _ = try await scratch.installFakeEngine()
        try await store.remove(id: "fake")
        #expect(try await store.installed().isEmpty)
        await #expect(throws: KoprikError.engineNotFound("fake")) { try await store.engine(id: "fake") }
    }

    @Test func prefersTheD3DMetalCapableEngine() async throws {
        let scratch = try Scratch()
        let store = EngineStore(paths: scratch.paths)
        _ = try await scratch.installFakeEngine(id: "plain")
        #expect(try await store.preferred()?.id == "plain")

        // Mark a second engine as CrossOver-derived by rewriting its manifest.
        let gaming = try await scratch.installFakeEngine(id: "gaming")
        var manifest = gaming.manifest
        manifest.d3dmetalCapable = true
        manifest.installedAt = .distantPast
        try JSONFile.write(manifest, to: gaming.directory.appending(path: Engine.manifestName))
        #expect(try await store.preferred()?.id == "gaming")
    }

    @Test func readsBundledComponentVersions() throws {
        let scratch = try Scratch()
        let plist: [String: Any] = [
            "gptkCapable": true, "dxvkVersion": "1.10.3", "dxmtVersion": "0.80",
            "version": ["major": 4, "minor": 8, "patch": 3],
        ]
        let folder = scratch.root.appending(path: "Libraries", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: folder.appending(path: "WhiskyWineVersion.plist"))

        #expect(EngineStore.bundledComponents(in: scratch.root) == ["dxvk": "1.10.3", "dxmt": "0.80", "runtime": "4.8.3"])
        #expect(EngineStore.bundledComponents(in: scratch.paths.root).isEmpty)
    }
}

@Suite struct DownloaderTests {
    @Test func downloadsAFileAndReportsProgress() async throws {
        let scratch = try Scratch()
        let source = scratch.root.appending(path: "source.bin")
        let payload = Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0) })
        try payload.write(to: source)
        let destination = scratch.root.appending(path: "nested/out.bin")

        let seen = Collector()
        try await Downloader.download(source, to: destination) { seen.add($0.receivedBytes) }

        #expect(try Data(contentsOf: destination) == payload)
        #expect(seen.values.last == Int64(payload.count))
    }

    @Test func replacesAnExistingFile() async throws {
        let scratch = try Scratch()
        let source = scratch.root.appending(path: "new.txt")
        try Data("new".utf8).write(to: source)
        let destination = scratch.root.appending(path: "out.txt")
        try Data("old content".utf8).write(to: destination)

        try await Downloader.download(source, to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "new")
    }

    @Test func failsForAMissingSource() async throws {
        let scratch = try Scratch()
        await #expect(throws: (any Error).self) {
            try await Downloader.download(scratch.root.appending(path: "missing.bin"), to: scratch.root.appending(path: "out"))
        }
    }
}

final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int64] = []
    func add(_ value: Int64) { lock.withLock { storage.append(value) } }
    var values: [Int64] { lock.withLock { storage } }
}
