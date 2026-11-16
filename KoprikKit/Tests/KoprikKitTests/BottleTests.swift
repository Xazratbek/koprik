import Foundation
import Testing
@testable import KoprikKit

@Suite struct BottleStoreTests {
    private func calls(in bottle: Bottle) throws -> [String] {
        try String(contentsOf: bottle.prefix.appending(path: "calls.log"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
    }

    @Test func createInitialisesThePrefixAndSetsTheWindowsVersion() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)

        let bottle = try await store.create(name: "Games", engine: engine, windowsVersion: .win11)

        #expect(bottle.config.engineID == "fake")
        #expect(FileManager.default.fileExists(atPath: bottle.prefix.appending(path: "system.reg").path))
        #expect(FileManager.default.fileExists(atPath: bottle.driveC.path))
        #expect(try calls(in: bottle) == ["wineboot --init", "winecfg -v win11"])

        let reloaded = try await store.bottle("games")
        #expect(reloaded.config == bottle.config)
        #expect(try await store.bottle(bottle.id.uuidString).id == bottle.id)
    }

    @Test func createRemovesTheBottleWhenWineFails() async throws {
        let scratch = try Scratch()
        let tree = try scratch.makeFakeWineTree(named: "broken")
        try scratch.writeExecutable("#!/bin/sh\necho boom\nexit 3\n", to: tree.appending(path: "bin/wine64"))
        let engine = try await EngineStore(paths: scratch.paths).importLocal(at: tree, id: "broken")
        let store = BottleStore(paths: scratch.paths)

        await #expect(throws: KoprikError.self) {
            try await store.create(name: "Doomed", engine: engine)
        }
        #expect(try await store.all().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.paths.bottles.path).isEmpty)
    }

    @Test func namesMustBeUniqueAndNonEmpty() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        _ = try await store.create(name: "Office", engine: engine)

        await #expect(throws: KoprikError.bottleNameTaken("OFFICE")) {
            try await store.create(name: "OFFICE", engine: engine)
        }
        await #expect(throws: KoprikError.self) {
            try await store.create(name: "   ", engine: engine)
        }
        await #expect(throws: KoprikError.bottleNotFound("nope")) { try await store.bottle("nope") }
    }

    @Test func renameKeepsTheBottleAndChecksForClashes() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        let first = try await store.create(name: "A", engine: engine)
        _ = try await store.create(name: "B", engine: engine)

        let renamed = try await store.rename(first, to: "C")
        #expect(renamed.id == first.id)
        #expect(try await store.all().map(\.name) == ["B", "C"])
        // Changing only the letter case of a bottle's own name is allowed.
        #expect(try await store.rename(renamed, to: "c").name == "c")
        await #expect(throws: KoprikError.bottleNameTaken("b")) { try await store.rename(renamed, to: "b") }
    }

    @Test func duplicateCopiesFilesAndIsIndependent() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        let original = try await store.create(name: "Original", engine: engine)
        let save = original.driveC.appending(path: "save.dat")
        try Data("level 1".utf8).write(to: save)
        // Wine prefixes are full of symlinks (dosdevices); they must be copied as links.
        try FileManager.default.createSymbolicLink(
            at: original.prefix.appending(path: "dosdevices/z:"), withDestinationURL: URL(fileURLWithPath: "/")
        )

        let copy = try await store.duplicate(original, as: "Copy")
        #expect(copy.id != original.id)
        #expect(copy.config.engineID == original.config.engineID)
        #expect(try String(contentsOf: copy.driveC.appending(path: "save.dat"), encoding: .utf8) == "level 1")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: copy.prefix.appending(path: "dosdevices/z:").path) == "/")

        try Data("level 2".utf8).write(to: copy.driveC.appending(path: "save.dat"))
        #expect(try String(contentsOf: save, encoding: .utf8) == "level 1")
    }

    @Test func snapshotAndRestoreRollTheBottleBack() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        let bottle = try await store.create(name: "Test", engine: engine)
        let config = bottle.driveC.appending(path: "config.ini")
        let installed = bottle.driveC.appending(path: "installed.exe")
        try Data("before".utf8).write(to: config)

        let snapshot = try await store.snapshot(bottle, label: "before install")
        #expect(try await store.snapshots(of: bottle).map(\.label) == ["before install"])

        try Data("after".utf8).write(to: config)
        try Data("x".utf8).write(to: installed)
        try await store.restore(bottle, snapshotID: snapshot.id)

        #expect(try String(contentsOf: config, encoding: .utf8) == "before")
        #expect(!FileManager.default.fileExists(atPath: installed.path))
        // The snapshot itself survives a restore and can be used again.
        #expect(try await store.snapshots(of: bottle).count == 1)
        let stray = try FileManager.default.contentsOfDirectory(atPath: bottle.directory.path)
            .filter { $0.hasPrefix(".prefix-replaced") }
        #expect(stray.isEmpty)
    }

    @Test func restoringAnUnknownSnapshotLeavesTheBottleUntouched() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        let bottle = try await store.create(name: "Test", engine: engine)
        try Data("keep".utf8).write(to: bottle.driveC.appending(path: "keep.txt"))

        await #expect(throws: KoprikError.snapshotNotFound("missing")) {
            try await store.restore(bottle, snapshotID: "missing")
        }
        #expect(FileManager.default.fileExists(atPath: bottle.driveC.appending(path: "keep.txt").path))
    }

    @Test func deleteSnapshotAndDeleteBottle() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let store = BottleStore(paths: scratch.paths)
        let bottle = try await store.create(name: "Gone", engine: engine)
        let snapshot = try await store.snapshot(bottle, label: "s")

        try await store.deleteSnapshot(bottle, snapshotID: snapshot.id)
        #expect(try await store.snapshots(of: bottle).isEmpty)
        try await store.delete(bottle, permanently: true)
        #expect(try await store.all().isEmpty)
    }
}

@Suite struct WineRunnerTests {
    @Test func startArgumentsOpenUnixPaths() {
        let file = URL(fileURLWithPath: "/Users/me/Downloads/Setup Wizard.exe")
        #expect(WineRunner.startArguments(for: file, programArguments: ["/S"])
            == ["start", "/wait", "/unix", "/Users/me/Downloads/Setup Wizard.exe", "/S"])
        #expect(WineRunner.startArguments(for: file, wait: false)
            == ["start", "/unix", "/Users/me/Downloads/Setup Wizard.exe"])
    }

    @Test func runWritesOutputToTheLogAndReturnsTheExitStatus() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let prefix = scratch.root.appending(path: "prefix", directoryHint: .isDirectory)
        let environment = WineEnvironment.build(engine: engine, prefix: prefix, settings: LaunchSettings())
        let log = scratch.root.appending(path: "logs/run.log")
        let runner = WineRunner(engine: engine)

        #expect(try await runner.run(["notepad.exe", "a b"], environment: environment, logURL: log) == 0)
        #expect(try await runner.run(["fail.exe"], environment: environment, logURL: log) == 7)

        let text = try String(contentsOf: log, encoding: .utf8)
        #expect(text.contains("fake wine ran: notepad.exe a b"))
        #expect(text.contains("fake wine ran: fail.exe"))
        // Each run is preceded by a header naming the command, and runs append.
        #expect(text.components(separatedBy: "--- ").count == 3)
    }

    @Test func outputLinesStreamTheLog() async throws {
        let scratch = try Scratch()
        let engine = try await scratch.installFakeEngine()
        let environment = WineEnvironment.build(
            engine: engine, prefix: scratch.root.appending(path: "p"), settings: LaunchSettings()
        )
        let process = try WineRunner(engine: engine).launch(
            ["hello.exe"], environment: environment, logURL: scratch.root.appending(path: "stream.log")
        )
        var lines: [String] = []
        for await line in process.outputLines(pollInterval: .milliseconds(20)) { lines.append(line) }
        #expect(await process.waitUntilExit() == 0)
        #expect(lines.contains("fake wine ran: hello.exe"))
    }

    @Test func launchFailsClearlyWhenTheEngineHasNoWine() async throws {
        let scratch = try Scratch()
        let engine = Engine(
            manifest: EngineManifest(id: "ghost", name: "Ghost", source: .local(path: "/nowhere"), d3dmetalCapable: false, wineRoot: ""),
            directory: scratch.root.appending(path: "ghost", directoryHint: .isDirectory)
        )
        #expect(throws: KoprikError.self) {
            try WineRunner(engine: engine).launch([], environment: [:], logURL: scratch.root.appending(path: "x.log"))
        }
    }
}
