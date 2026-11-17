import Foundation
import Testing
@testable import KoprikKit

@Suite struct StoreTests {
    @Test func epicCodeIsTakenFromTheLoginPageJSONOrUsedAsIs() {
        #expect(EpicStore.extractCode(#"{"redirectUrl":"x","authorizationCode":"abc123","sid":null}"#) == "abc123")
        #expect(EpicStore.extractCode("  abc123\n") == "abc123")
        #expect(EpicStore.extractCode("\"abc123\"") == "abc123")
    }

    @Test func gogCodeIsTakenFromTheRedirectAddress() {
        #expect(GOGStore.extractCode("https://embed.gog.com/on_login_success?origin=client&code=XYZ_9") == "XYZ_9")
        #expect(GOGStore.extractCode("XYZ_9") == "XYZ_9")
    }

    @Test func parsesLegendaryLibrary() {
        let json = """
        [{"app_name":"Sugar","app_title":"Zeta Game","metadata":{"keyImages":[{"type":"DieselGameBox","url":"https://a/wide.jpg"},{"type":"DieselGameBoxTall","url":"https://a/tall.jpg"}]}},
         {"app_name":"Fig","app_title":"Alpha Game"}]
        """
        let games = EpicStore.parseLibrary(json)
        #expect(games.map(\.title) == ["Alpha Game", "Zeta Game"])
        #expect(games.last?.coverURL?.absoluteString == "https://a/tall.jpg")
        #expect(games.allSatisfy { $0.store == .epic && !$0.isInstalled })
    }

    @Test func parsesLegendaryLaunchParametersAfterLogLines() {
        let output = """
        [cli] INFO: Logging in...
        {"game_executable": "Bin/Game.exe", "game_directory": "/games/Sugar", "game_parameters": ["-nosplash"],
         "egl_parameters": ["-AUTH_PASSWORD=t0k3n", "-epicapp=Sugar"], "user_parameters": [], "working_directory": "",
         "launch_command": ["wine"], "environment": {}}
        """
        let launch = EpicStore.parseLaunch(output)
        #expect(launch?.executable.path == "/games/Sugar/Bin/Game.exe")
        #expect(launch?.workingDirectory.path == "/games/Sugar")
        #expect(launch?.arguments == ["-nosplash", "-AUTH_PASSWORD=t0k3n", "-epicapp=Sugar"])
    }

    @Test func readsTheGOGPrimaryPlayTask() {
        let info = """
        {"gameId":"1207658924","name":"Example","playTasks":[
          {"category":"tool","name":"Manual","type":"URLTask","link":"https://x"},
          {"category":"game","isPrimary":true,"name":"Example","path":"bin\\\\example.exe","workingDir":"bin","arguments":"-windowed -skip","type":"FileTask"}]}
        """
        let launch = GOGStore.parseInfo(Data(info.utf8), folder: URL(fileURLWithPath: "/games/Example"))
        #expect(launch?.executable.path == "/games/Example/bin/example.exe")
        #expect(launch?.workingDirectory.path == "/games/Example/bin")
        #expect(launch?.arguments == ["-windowed", "-skip"])
    }

    @Test func findsInstalledGOGGamesByTheirInfoFile() throws {
        let scratch = try Scratch()
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "b"))
        let folder = bottle.driveC.appending(path: "Games/GOG/Example", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: folder.appending(path: "goggame-1207658924.info"))
        #expect(GOGStore.installedGames(in: [bottle])["1207658924"]?.lastPathComponent == "Example")
    }
}

@Suite struct WhiskyAndSavesTests {
    @Test func readsWhiskyBottlesAndImportsACopy() async throws {
        let scratch = try Scratch()
        let container = scratch.root.appending(path: "Whisky", directoryHint: .isDirectory)
        let source = container.appending(path: "Bottles/ABC", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source.appending(path: "drive_c/windows"), withIntermediateDirectories: true)
        try Data("REGEDIT4".utf8).write(to: source.appending(path: "system.reg"))
        let metadata: [String: Any] = ["info": ["name": "Old Games"], "wineConfig": ["windowsVersion": "win7"]]
        try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
            .write(to: source.appending(path: "Metadata.plist"))
        let list: [String: Any] = ["fileVersion": "1.0.0", "paths": [["relative": source.absoluteString]]]
        try PropertyListSerialization.data(fromPropertyList: list, format: .xml, options: 0)
            .write(to: container.appending(path: "BottleVM.plist"))

        let found = WhiskyImport.bottles(container: container)
        #expect(found.count == 1)
        #expect(found.first?.name == "Old Games")
        #expect(found.first?.windowsVersion == .win7)

        let engine = try await scratch.installFakeEngine()
        let imported = try await BottleStore(paths: scratch.paths).importWhisky(try #require(found.first), engine: engine)
        #expect(imported.name == "Old Games")
        #expect(FileManager.default.fileExists(atPath: imported.prefix.appending(path: "system.reg").path))
        #expect(!FileManager.default.fileExists(atPath: imported.prefix.appending(path: "Metadata.plist").path))
        #expect(FileManager.default.fileExists(atPath: source.appending(path: "Metadata.plist").path))
    }

    @Test func backsUpSavesWithoutCaches() async throws {
        let scratch = try Scratch()
        let bottle = Bottle(config: BottleConfig(name: "Games", engineID: "e"), directory: scratch.root.appending(path: "b"))
        let user = bottle.driveC.appending(path: "users/player", directoryHint: .isDirectory)
        for (path, text) in ["Saved Games/Game/slot1.sav": "save", "AppData/Local/Temp/junk.tmp": "junk"] {
            let url = user.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let tools = BottleTools(bottle: bottle, engine: sampleEngine())
        let archive = try await tools.backupSaves(to: scratch.root.appending(path: "backups"))
        let listing = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/tar"), arguments: ["-tf", archive.path]).stdout
        #expect(listing.contains("player/Saved Games/Game/slot1.sav"))
        #expect(!listing.contains("junk.tmp"))

        try FileManager.default.removeItem(at: user.appending(path: "Saved Games"))
        try await tools.restoreSaves(from: archive)
        #expect(try String(contentsOf: user.appending(path: "Saved Games/Game/slot1.sav"), encoding: .utf8) == "save")
    }
}

@Suite struct LinkBridgeTests {
    private let registry = #"""
    [Software\\Classes\\notion] 1794922810
    @="URL:notion"
    "URL Protocol"=""

    [Software\\Classes\\notion\\shell\\open\\command] 1794922810
    @="\"C:\\users\\crossover\\AppData\\Local\\Programs\\Notion\\Notion.exe\" \"%1\""

    [Software\\Classes\\https] 1
    "URL Protocol"=""

    [Software\\Classes\\.txt] 1
    @="txtfile"
    """#

    @Test func findsRegisteredSchemesButNotWebOnes() {
        #expect(LinkBridge.schemes(inRegistry: registry) == ["notion", "https"])
    }

    @Test func readsTheHandlerCommand() {
        #expect(LinkBridge.command(for: "notion", inRegistry: registry)
            == #""C:\users\crossover\AppData\Local\Programs\Notion\Notion.exe" "%1""#)
    }

    @Test func forwardedLinksKeepTheirOwnSlashes() throws {
        let id = UUID()
        let url = try #require(URL(string: "koprik://open-url/\(id.uuidString)/notion://www.notion.so/login?code=a%2Fb"))
        let parsed = LinkBridge.parseForwarded(url)
        #expect(parsed?.bottleID == id)
        #expect(parsed?.link == "notion://www.notion.so/login?code=a%2Fb")
        #expect(LinkBridge.parseForwarded(try #require(URL(string: "koprik://open-url/\(id.uuidString)/https://evil.example"))) == nil)
    }
}

@Suite struct IsolationTests {
    private let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
    private var bottle: Bottle {
        Bottle(config: BottleConfig(name: "Sandbox", engineID: "e"), directory: URL(fileURLWithPath: "/Users/someone/Library/Application Support/Koprik/Bottles/X", isDirectory: true))
    }

    @Test func blocksTheHomeFolderAndForeignProgramsButKeepsTheBottle() {
        let profile = Sandbox.profile(for: bottle, engine: sampleEngine(), isolation: .files, home: home)
        #expect(profile.contains(#"(deny file-read* file-write* (subpath "/Users/someone"))"#))
        #expect(profile.contains(#"(allow file-write* (subpath "/Users/someone/Library/Application Support/Koprik/Bottles/X")"#))
        #expect(profile.contains("(deny process-exec*)"))
        #expect(profile.contains(#"(allow process-exec* (subpath "/engines/sample"))"#))
        #expect(profile.contains("(deny appleevent-send)"))
        #expect(!profile.contains("network"))
        // Documents is not on the allowlist.
        #expect(!profile.contains("Documents"))
    }

    @Test func strictIsolationAlsoCutsTheNetwork() {
        let profile = Sandbox.profile(for: bottle, engine: sampleEngine(), isolation: .full, home: home)
        #expect(profile.contains("(deny network-outbound (remote ip))"))
    }

    @Test func onlyIsolatedBottlesGetASandboxedRunner() {
        var config = BottleConfig(name: "B", engineID: "e")
        #expect(WineRunner.forBottle(Bottle(config: config, directory: home), engine: sampleEngine()).sandboxProfile == nil)
        config.isolation = .files
        #expect(WineRunner.forBottle(Bottle(config: config, directory: home), engine: sampleEngine()).sandboxProfile != nil)
    }

    @Test func aSandboxedProcessCannotWriteOutsideItsBottle() async throws {
        let scratch = try Scratch()
        let bottle = Bottle(config: BottleConfig(name: "B", engineID: "e"), directory: scratch.root.appending(path: "bottle", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: bottle.directory, withIntermediateDirectories: true)
        let outside = scratch.root.appending(path: "outside.txt")
        let inside = bottle.directory.appending(path: "inside.txt")
        // The "home" is the scratch root, so everything outside the bottle in it is off limits.
        let profile = Sandbox.profile(for: bottle, engine: sampleEngine(), isolation: .files, home: scratch.root)
            .replacingOccurrences(of: "(deny process-exec*)", with: "")
        let script = "echo x > '\(outside.path)'; echo x > '\(inside.path)'"
        _ = try await ProcessRunner.run(Sandbox.executable, arguments: ["-p", profile, "/bin/sh", "-c", script])
        #expect(!FileManager.default.fileExists(atPath: outside.path))
        #expect(FileManager.default.fileExists(atPath: inside.path))
    }
}
