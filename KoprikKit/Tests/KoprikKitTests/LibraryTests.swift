import Foundation
import Testing
@testable import KoprikKit

@Suite struct VDFTests {
    @Test func parsesNestedObjectsQuotesAndComments() {
        let text = """
        // a comment
        "libraryfolders"
        {
            "0"
            {
                "path"      "C:\\\\Program Files (x86)\\\\Steam"
                "apps" { "480" "1024" }
            }
        }
        """
        let root = VDFValue.parse(text)
        #expect(root["libraryfolders"]?["0"]?["path"]?.string == "C:\\Program Files (x86)\\Steam")
        #expect(root["LibraryFolders"]?["0"]?["apps"]?["480"]?.string == "1024")
    }

    @Test func readsAnAppManifest() {
        let text = """
        "AppState"
        {
            "appid"     "291550"
            "name"      "Brawlhalla"
            "StateFlags"    "4"
            "installdir"    "Brawlhalla"
            "SizeOnDisk"    "812345678"
        }
        """
        let app = SteamLibrary.parseManifest(text, steamapps: URL(fileURLWithPath: "/lib/steamapps"))
        #expect(app?.appID == 291550)
        #expect(app?.name == "Brawlhalla")
        #expect(app?.installDirectory.path == "/lib/steamapps/common/Brawlhalla")
        #expect(app?.isFullyInstalled == true)
        #expect(app?.sizeOnDisk == 812_345_678)
    }

    @Test func aManifestStillDownloadingIsNotFullyInstalled() {
        let text = "\"AppState\" { \"appid\" \"10\" \"name\" \"X\" \"StateFlags\" \"1026\" \"installdir\" \"X\" }"
        #expect(SteamLibrary.parseManifest(text, steamapps: URL(fileURLWithPath: "/s"))?.isFullyInstalled == false)
    }

    @Test func garbageYieldsNoManifest() {
        #expect(SteamLibrary.parseManifest("not vdf at all {{{", steamapps: URL(fileURLWithPath: "/s")) == nil)
    }
}

@Suite struct ShellLinkTests {
    /// Builds a minimal shortcut with a local base path and Unicode string data.
    private func makeLink(target: String, arguments: String?, workingDirectory: String?) -> Data {
        var flags: UInt32 = 0x02 | 0x80 // HasLinkInfo, IsUnicode
        if workingDirectory != nil { flags |= 0x10 }
        if arguments != nil { flags |= 0x20 }

        var data = Data()
        PEFile.append32(&data, 0x4C)
        data.append(Data(repeating: 0, count: 16))
        PEFile.append32(&data, flags)
        data.append(Data(repeating: 0, count: 76 - data.count))

        let path = Data(target.utf8) + [0]
        let headerSize: UInt32 = 0x1C
        var info = Data()
        PEFile.append32(&info, headerSize + UInt32(path.count) + 1)
        PEFile.append32(&info, headerSize)
        PEFile.append32(&info, 0x01) // VolumeIDAndLocalBasePath
        PEFile.append32(&info, 0)
        PEFile.append32(&info, headerSize) // LocalBasePathOffset
        PEFile.append32(&info, 0)
        PEFile.append32(&info, headerSize + UInt32(path.count)) // CommonPathSuffixOffset -> empty string
        info.append(path)
        info.append(0)
        data.append(info)

        for string in [workingDirectory, arguments].compactMap({ $0 }) {
            let units = Array(string.utf16)
            PEFile.append16(&data, UInt16(units.count))
            for unit in units { PEFile.append16(&data, unit) }
        }
        return data
    }

    @Test func readsTargetArgumentsAndWorkingDirectory() {
        let link = ShellLink(data: makeLink(
            target: "C:\\Program Files\\7-Zip\\7zFM.exe", arguments: "-x \"my file\"", workingDirectory: "C:\\Program Files\\7-Zip"
        ))
        #expect(link?.targetPath == "C:\\Program Files\\7-Zip\\7zFM.exe")
        #expect(link?.arguments == "-x \"my file\"")
        #expect(link?.workingDirectory == "C:\\Program Files\\7-Zip")
    }

    @Test func rejectsFilesThatAreNotShortcuts() {
        #expect(ShellLink(data: Data("MZ this is an exe".utf8)) == nil)
        #expect(ShellLink(data: Data()) == nil)
    }

    @Test func splitsCommandLinesOnSpacesOutsideQuotes() {
        #expect(ProgramStore.splitArguments("-a  \"two words\" -b") == ["-a", "two words", "-b"])
        #expect(ProgramStore.splitArguments("") == [])
    }
}

@Suite struct WindowsPathTests {
    @Test func mapsBetweenWindowsAndHostPaths() throws {
        let scratch = try Scratch()
        let prefix = scratch.root.appending(path: "prefix", directoryHint: .isDirectory)
        let driveC = prefix.appending(path: "drive_c/Program Files/App", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: driveC, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appending(path: "dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: prefix.appending(path: "dosdevices/c:").path, withDestinationPath: "../drive_c")
        let exe = driveC.appending(path: "app.exe")
        try Data().write(to: exe)

        let host = WindowsPath.hostURL(for: "C:\\Program Files\\App\\app.exe", prefix: prefix)
        #expect(host?.resolvingSymlinksInPath().path == exe.resolvingSymlinksInPath().path)
        #expect(WindowsPath.windowsPath(for: exe, prefix: prefix) == "C:\\Program Files\\App\\app.exe")
        #expect(WindowsPath.hostURL(for: "relative\\path.exe", prefix: prefix) == nil)
        #expect(WindowsPath.windowsPath(for: URL(fileURLWithPath: "/Applications/x.exe"), prefix: prefix) == nil)
    }
}

@Suite struct PEFileTests {
    @Test func rejectsDataThatIsNotAnExecutable() {
        #expect(PEFile(data: Data()) == nil)
        #expect(PEFile(data: Data("#!/bin/sh\necho hi\n".utf8)) == nil)
        // "MZ" with a header pointer far outside the file must not crash.
        var truncated = Data("MZ".utf8) + Data(repeating: 0, count: 0x40)
        truncated[0x3C] = 0xFF
        truncated[0x3D] = 0xFF
        #expect(PEFile(data: truncated) == nil)
    }

    /// Runs against a real Wine build when one is installed on this Mac; the
    /// file is too intricate to fake convincingly.
    @Test func readsImportsAndIconFromARealExecutable() throws {
        let engines = AppPaths.default.engines
        guard let enumerator = FileManager.default.enumerator(at: engines, includingPropertiesForKeys: nil) else { return }
        var notepad: URL?
        for case let url as URL in enumerator where url.path.hasSuffix("x86_64-windows/notepad.exe") {
            notepad = url
            break
        }
        guard let notepad else { return }

        let file = try #require(PEFile(url: notepad))
        #expect(file.is64Bit)
        #expect(file.architecture == .x86_64)
        #expect(file.importedLibraries.contains("user32.dll"))
        let icon = try #require(file.iconFileData)
        #expect(icon.prefix(4) == Data([0, 0, 1, 0]))
    }
}

@Suite struct LogAnalyzerTests {
    @Test func recognisesAMissingRuntimeAndSuggestsTheVerb() {
        let log = """
        0024:err:module:import_dll Library VCRUNTIME140.dll (which is needed by L"C:\\\\game\\\\game.exe") not found
        0024:err:module:loader_init Importing dlls for L"C:\\\\game\\\\game.exe" failed, status c0000135
        """
        let summary = LogAnalyzer.analyze(log)
        #expect(summary.missingLibraries == ["vcruntime140.dll"])
        #expect(summary.findings.first { $0.id == "vcrun" }?.suggestedVerb == "vcrun2022")
        #expect(summary.errorLines == 2)
    }

    @Test func flagsAntiCheat() {
        let summary = LogAnalyzer.analyze("0100:fixme:ntoskrnl:load_driver EasyAntiCheat.sys could not be started")
        #expect(summary.findings.first?.id == "anticheat")
        #expect(summary.findings.first?.severity == .error)
    }

    @Test func aCleanLogHasNoFindings() {
        let summary = LogAnalyzer.analyze("[mvk-info] MoltenVK version 1.4.2\nwine: configuration in /prefix has been updated.")
        #expect(summary.findings.isEmpty)
        #expect(summary.lineCount == 2)
    }

    @Test func aDllNameAloneIsNotAFinding() {
        let summary = LogAnalyzer.analyze("0024:trace:module:load_dll Loaded L\"C:\\\\windows\\\\system32\\\\vcruntime140.dll\" at 0x7f : native")
        #expect(summary.findings.isEmpty)
    }
}

@Suite struct IntegrationTests {
    @Test func launcherLinksRoundTrip() {
        let id = UUID()
        let url = AppLauncherBuilder.launchURL(bottleID: id, programID: "steam-440")
        let parsed = AppLauncherBuilder.parse(url)
        #expect(parsed?.bottleID == id)
        #expect(parsed?.programID == "steam-440")
        #expect(AppLauncherBuilder.parse(URL(string: "koprik://show/install")!) == nil)
        #expect(AppLauncherBuilder.parse(URL(string: "https://example.com/run/x/y")!) == nil)
    }

    @Test func createsALaunchableBundle() throws {
        let scratch = try Scratch()
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "b"))
        let program = Program(id: "exe-1", name: "My: Game/2", location: "C:\\g.exe")
        let bundle = try AppLauncherBuilder.create(for: program, in: bottle, folder: scratch.root.appending(path: "apps"))

        #expect(bundle.lastPathComponent == "My- Game-2.app")
        let script = try String(contentsOf: bundle.appending(path: "Contents/MacOS/launch"), encoding: .utf8)
        #expect(script.contains("koprik://run/\(bottle.id.uuidString)/exe-1"))
        #expect(FileManager.default.isExecutableFile(atPath: bundle.appending(path: "Contents/MacOS/launch").path))
        #expect(FileManager.default.fileExists(atPath: bundle.appending(path: "Contents/Info.plist").path))
    }

    @Test func builtinRecipesAreWellFormed() throws {
        let recipes = RecipeLibrary.all()
        #expect(Set(recipes.map(\.id)).count == recipes.count)
        for recipe in recipes {
            #expect(recipe.download != nil || !recipe.winetricks.isEmpty, "\(recipe.id) does nothing")
            if let url = recipe.download?.url { #expect(url.scheme == "https") }
            let decoded = try JSONDecoder().decode(Recipe.self, from: JSONEncoder().encode(recipe))
            #expect(decoded == recipe)
        }
    }
}

@Suite struct ProgramStoreTests {
    private func makeBottle(_ scratch: Scratch) throws -> Bottle {
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "bottle"))
        try FileManager.default.createDirectory(at: bottle.driveC.appending(path: "app"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottle.prefix.appending(path: "dosdevices"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: bottle.prefix.appending(path: "dosdevices/c:").path, withDestinationPath: "../drive_c")
        try Data().write(to: bottle.driveC.appending(path: "app/tool.exe"))
        return bottle
    }

    @Test func pinnedProgramsPersistAndStatisticsAccumulate() async throws {
        let scratch = try Scratch()
        let bottle = try makeBottle(scratch)
        let store = ProgramStore()

        let pinned = try await store.pin(executable: bottle.driveC.appending(path: "app/tool.exe"), in: bottle)
        #expect(pinned.location == "C:\\app\\tool.exe")
        #expect(await store.programs(in: bottle).map(\.name) == ["tool"])

        let started = Date.now
        _ = try await store.recordSession(programID: pinned.id, in: bottle, started: started, duration: 90)
        _ = try await store.recordSession(programID: pinned.id, in: bottle, started: started, duration: 30)
        let updated = try #require(await store.program(id: pinned.id, in: bottle))
        #expect(updated.launchCount == 2)
        #expect(updated.playTime == 120)
    }

    @Test func hiddenProgramsAreLeftOutUnlessAskedFor() async throws {
        let scratch = try Scratch()
        let bottle = try makeBottle(scratch)
        let store = ProgramStore()
        var program = try await store.pin(executable: bottle.driveC.appending(path: "app/tool.exe"), in: bottle)
        program.hidden = true
        try await store.save(program, in: bottle)

        #expect(await store.programs(in: bottle).isEmpty)
        #expect(await store.programs(in: bottle, includeHidden: true).count == 1)
    }

    @Test func findsSteamGamesFromManifests() async throws {
        let scratch = try Scratch()
        let bottle = try makeBottle(scratch)
        let steam = bottle.driveC.appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: steam.appending(path: "steamapps/common/Brawlhalla"), withIntermediateDirectories: true)
        try Data().write(to: steam.appending(path: "steam.exe"))
        try "\"AppState\" { \"appid\" \"291550\" \"name\" \"Brawlhalla\" \"StateFlags\" \"4\" \"installdir\" \"Brawlhalla\" }"
            .write(to: steam.appending(path: "steamapps/appmanifest_291550.acf"), atomically: true, encoding: .utf8)
        // Steam's shared redistributables are listed like a game and must be skipped.
        try "\"AppState\" { \"appid\" \"228980\" \"name\" \"Steamworks Common Redistributables\" \"StateFlags\" \"4\" \"installdir\" \"Steamworks Shared\" }"
            .write(to: steam.appending(path: "steamapps/appmanifest_228980.acf"), atomically: true, encoding: .utf8)

        let programs = await ProgramStore().programs(in: bottle)
        #expect(programs.map(\.name) == ["Brawlhalla"])
        #expect(programs.first?.kind == .steam)
        #expect(programs.first?.id == "steam-291550")
    }
}

@Suite struct GraphicsTests {
    /// An engine laid out like winecx-gptk: `Libraries/Wine` beside `Libraries/DXMT` and `Libraries/DXVK`.
    private func makeEngine(_ scratch: Scratch) throws -> Engine {
        let libraries = scratch.root.appending(path: "engine/Libraries", directoryHint: .isDirectory)
        let files = [
            "Wine/lib/wine/x86_64-windows/d3d11.dll": "builtin-d3d11",
            "Wine/lib/wine/x86_64-windows/dxgi.dll": "builtin-dxgi",
            "Wine/lib/wine/x86_64-windows/winemetal.dll": "builtin-winemetal",
            "DXMT/x64/d3d11.dll": "dxmt-d3d11",
            "DXMT/x64/dxgi.dll": "dxmt-dxgi",
            "DXMT/x64/nvngx.dll": "dxmt-nvngx",
            "DXVK/x64/d3d11.dll": "dxvk-d3d11",
        ]
        for (path, content) in files {
            let url = libraries.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return Engine(
            manifest: EngineManifest(id: "e", name: "E", source: .winecxGPTK(tag: "t"), d3dmetalCapable: true, wineRoot: "Libraries/Wine"),
            directory: scratch.root.appending(path: "engine", directoryHint: .isDirectory)
        )
    }

    private func read(_ name: String, in prefix: URL) -> String? {
        try? String(contentsOf: prefix.appending(path: "drive_c/windows/system32/\(name)"), encoding: .utf8)
    }

    @Test func reportsWhatTheEngineOffers() throws {
        let scratch = try Scratch()
        let capabilities = Graphics.capabilities(of: try makeEngine(scratch))
        #expect(capabilities.dxmt)
        #expect(capabilities.dxvk)
        #expect(!capabilities.d3dmetal)
    }

    @Test func switchingBackendsSwapsFilesAndRestoresWineOwnCopies() throws {
        let scratch = try Scratch()
        let engine = try makeEngine(scratch)
        let prefix = scratch.root.appending(path: "prefix", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: prefix.appending(path: "drive_c/windows/system32"), withIntermediateDirectories: true)

        try Graphics.prepare(.dxmt, engine: engine, prefix: prefix)
        #expect(read("d3d11.dll", in: prefix) == "dxmt-d3d11")
        #expect(read("dxgi.dll", in: prefix) == "dxmt-dxgi")
        #expect(read("nvngx.dll", in: prefix) == "dxmt-nvngx")

        // DXVK ships no dxgi of its own here, so Wine's must come back, and DXMT's extra file must go.
        try Graphics.prepare(.dxvk, engine: engine, prefix: prefix)
        #expect(read("d3d11.dll", in: prefix) == "dxvk-d3d11")
        #expect(read("dxgi.dll", in: prefix) == "builtin-dxgi")
        #expect(read("nvngx.dll", in: prefix) == nil)

        try Graphics.prepare(.wined3d, engine: engine, prefix: prefix)
        #expect(read("d3d11.dll", in: prefix) == "builtin-d3d11")
        #expect(read("winemetal.dll", in: prefix) == "builtin-winemetal")
    }

    @Test func anUnavailableBackendFallsBackWithAnExplanation() throws {
        let scratch = try Scratch()
        let decision = Graphics.decide(requested: .d3dmetal, engine: try makeEngine(scratch), executables: [])
        #expect(decision.backend == .dxmt)
        #expect(decision.reason.contains("D3DMetal is not available"))
    }

    @Test func storeLaunchersGetDXVKUnlessTheUserChoseOtherwise() throws {
        let scratch = try Scratch()
        let engine = try makeEngine(scratch)
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "b"))
        let launcher = Launcher(bottle: bottle, engine: engine)
        let steam = Program(id: "x", name: "Steam", location: "C:\\Program Files (x86)\\Steam\\steam.exe")
        let game = Program(id: "steam-1", name: "Game", kind: .steam, location: "/nowhere", steamAppID: 1)

        #expect(launcher.graphicsDecision(for: .program(steam)).backend == .dxvk)
        // Games from Steam are started directly and choose like any other program.
        #expect(launcher.graphicsDecision(for: .program(game)).backend == .dxmt)
        #expect(launcher.graphicsDecision(for: .program(steam), overrides: LaunchSettings(backend: .wined3d)).backend == .wined3d)
        #expect(launcher.graphicsDecision(for: .command("notepad", arguments: [])).backend == .dxmt)
    }
}

@Suite struct LocalGraphicsTests {
    private func makeEngine(_ scratch: Scratch) throws -> Engine {
        let libraries = scratch.root.appending(path: "engine/Libraries", directoryHint: .isDirectory)
        for (path, content) in ["DXMT/x64/d3d11.dll": "dxmt-d3d11", "DXMT/x64/dxgi.dll": "dxmt-dxgi", "Wine/bin/.keep": ""] {
            let url = libraries.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
        }
        return Engine(
            manifest: EngineManifest(id: "e", name: "E", source: .winecxGPTK(tag: "t"), d3dmetalCapable: true, wineRoot: "Libraries/Wine"),
            directory: scratch.root.appending(path: "engine", directoryHint: .isDirectory)
        )
    }

    @Test func placesAndRemovesOnlyItsOwnFiles() throws {
        let scratch = try Scratch()
        let engine = try makeEngine(scratch)
        let game = scratch.root.appending(path: "game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        // The game ships its own dxgi.dll, which must survive.
        try Data("game-dxgi".utf8).write(to: game.appending(path: "dxgi.dll"))

        try Graphics.prepareLocal(.dxmt, engine: engine, directory: game)
        #expect(try String(contentsOf: game.appending(path: "d3d11.dll"), encoding: .utf8) == "dxmt-d3d11")
        #expect(try String(contentsOf: game.appending(path: "dxgi.dll"), encoding: .utf8) == "game-dxgi")

        try Graphics.clearLocal(in: game)
        #expect(!FileManager.default.fileExists(atPath: game.appending(path: "d3d11.dll").path))
        #expect(try String(contentsOf: game.appending(path: "dxgi.dll"), encoding: .utf8) == "game-dxgi")
        #expect(!FileManager.default.fileExists(atPath: game.appending(path: Graphics.localMarkerName).path))
    }

    @Test func steamOverlaySwitchEditsEveryAccount() throws {
        let scratch = try Scratch()
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "b"))
        let steam = bottle.driveC.appending(path: "Program Files (x86)/Steam", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: steam.appending(path: "userdata/1/config"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: steam.appending(path: "userdata/2/config"), withIntermediateDirectories: true)
        try Data().write(to: steam.appending(path: "steam.exe"))
        let fresh = "\"UserLocalConfigStore\"\n{\n\t\"system\"\n\t{\n\t\t\"PushToTalkKey\"\t\t\"0\"\n\t}\n}\n"
        try fresh.write(to: steam.appending(path: "userdata/1/config/localconfig.vdf"), atomically: true, encoding: .utf8)
        try fresh.replacingOccurrences(of: "\t\t\"PushToTalkKey\"", with: "\t\t\"EnableGameOverlay\"\t\t\"1\"\n\t\t\"PushToTalkKey\"")
            .write(to: steam.appending(path: "userdata/2/config/localconfig.vdf"), atomically: true, encoding: .utf8)

        SteamLibrary.setGameOverlay(enabled: false, in: bottle)
        for account in ["1", "2"] {
            let text = try String(contentsOf: steam.appending(path: "userdata/\(account)/config/localconfig.vdf"), encoding: .utf8)
            #expect(VDFValue.parse(text)["UserLocalConfigStore"]?["system"]?["EnableGameOverlay"]?.string == "0")
            #expect(VDFValue.parse(text)["UserLocalConfigStore"]?["system"]?["PushToTalkKey"]?.string == "0")
        }
    }

    @Test func picksTheMainGameExecutable() throws {
        let scratch = try Scratch()
        let game = scratch.root.appending(path: "Game", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game.appending(path: "redist"), withIntermediateDirectories: true)
        try Data(count: 3 << 20).write(to: game.appending(path: "Game.exe"))
        try Data(count: 1 << 20).write(to: game.appending(path: "CrashReporter.exe"))
        try Data(count: 9 << 20).write(to: game.appending(path: "redist/vc_redist.x64.exe"))
        #expect(Launcher.mainExecutable(ofSteamGameAt: game)?.lastPathComponent == "Game.exe")
    }
}

@Suite struct SteamExecutableTests {
    @Test func aSmallExecutableNamedLikeTheGameWins() throws {
        let scratch = try Scratch()
        let game = scratch.root.appending(path: "Brawlhalla", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: game.appending(path: "Adobe AIR"), withIntermediateDirectories: true)
        try Data(count: 185 * 1024).write(to: game.appending(path: "Brawlhalla.exe"))
        try Data(count: 4 << 20).write(to: game.appending(path: "Adobe AIR/Helper.exe"))
        #expect(Launcher.mainExecutable(ofSteamGameAt: game)?.lastPathComponent == "Brawlhalla.exe")
    }
}

@Suite struct ChromiumArgumentTests {
    @Test func electronAppsGetTheirGPUInProcess() throws {
        let scratch = try Scratch()
        let app = scratch.root.appending(path: "Notion", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        for file in ["Notion.exe", "resources.pak", "snapshot_blob.bin"] {
            try Data().write(to: app.appending(path: file))
        }
        let exe = app.appending(path: "Notion.exe")
        #expect(Launcher.chromiumArguments(for: exe, ["notion://x"]) == ["--in-process-gpu", "notion://x"])
        #expect(Launcher.chromiumArguments(for: exe, ["--in-process-gpu"]) == ["--in-process-gpu"])
    }

    @Test func otherProgramsKeepTheirArguments() throws {
        let scratch = try Scratch()
        let exe = scratch.root.appending(path: "game.exe")
        try Data().write(to: exe)
        #expect(Launcher.chromiumArguments(for: exe, ["-windowed"]) == ["-windowed"])
    }
}

@Suite struct ImportFolderTests {
    @Test func aProgramsOwnFolderIsCopiedWholeButCatchAllFoldersAreNot() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(Launcher.isOwnFolder(URL(fileURLWithPath: "/Users/someone/Downloads/Game [Repack]"), home: home))
        #expect(Launcher.isOwnFolder(URL(fileURLWithPath: "/Volumes/GameDisc"), home: home))
        #expect(!Launcher.isOwnFolder(URL(fileURLWithPath: "/Users/someone/Downloads"), home: home))
        #expect(!Launcher.isOwnFolder(URL(fileURLWithPath: "/Users/someone/Desktop/"), home: home))
        #expect(!Launcher.isOwnFolder(URL(fileURLWithPath: "/Users/someone"), home: home))
        #expect(!Launcher.isOwnFolder(URL(fileURLWithPath: "/Volumes"), home: home))
    }
}

@Suite struct ShortcutNameTests {
    @Test func dropsTheVerbInstallersPutInFront() {
        #expect(ProgramStore.displayName(fromShortcut: "Start game Need for Speed - Most Wanted") == "Need for Speed - Most Wanted")
        #expect(ProgramStore.displayName(fromShortcut: "Play Brawlhalla") == "Brawlhalla")
        #expect(ProgramStore.displayName(fromShortcut: "Startup Manager") == "Startup Manager")
        #expect(ProgramStore.displayName(fromShortcut: "Notepad++") == "Notepad++")
    }
}
