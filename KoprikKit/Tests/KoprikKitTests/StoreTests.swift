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
