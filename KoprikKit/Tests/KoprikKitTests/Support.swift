import Foundation
@testable import KoprikKit

/// A scratch `AppPaths` root that is deleted when the value goes away.
final class Scratch {
    let root: URL
    let paths: AppPaths

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "koprik-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        paths = AppPaths(root: root.appending(path: "home", directoryHint: .isDirectory))
        try paths.ensureDirectories()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes a stand-in Wine tree whose `wine64` is a shell script.
    ///
    /// The script records every call in `$WINEPREFIX/calls.log` and creates the
    /// files a real `wineboot` would, which is enough to exercise the stores
    /// without Wine or Rosetta.
    @discardableResult
    func makeFakeWineTree(named name: String = "fake-wine", nestedUnder nesting: String? = nil) throws -> URL {
        let tree = root.appending(path: name, directoryHint: .isDirectory)
        let wineRoot = nesting.map { tree.appending(path: $0, directoryHint: .isDirectory) } ?? tree
        let bin = wineRoot.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)

        let wine = """
        #!/bin/sh
        if [ "$1" = "--version" ]; then echo "wine-11.19 (fake)"; exit 0; fi
        if [ -n "$WINEPREFIX" ]; then
          mkdir -p "$WINEPREFIX/drive_c/windows" "$WINEPREFIX/dosdevices"
          echo "$@" >> "$WINEPREFIX/calls.log"
          [ -f "$WINEPREFIX/system.reg" ] || echo "WINE REGISTRY Version 2" > "$WINEPREFIX/system.reg"
        fi
        echo "fake wine ran: $@"
        if [ "$1" = "fail.exe" ]; then exit 7; fi
        exit 0
        """
        try writeExecutable(wine, to: bin.appending(path: "wine64"))
        try writeExecutable("#!/bin/sh\nexit 0\n", to: bin.appending(path: "wineserver"))
        return tree
    }

    func writeExecutable(_ script: String, to url: URL) throws {
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    func installFakeEngine(id: String = "fake") async throws -> Engine {
        try await EngineStore(paths: paths).importLocal(at: try makeFakeWineTree(named: "tree-\(id)"), id: id)
    }
}

func sampleEngine(source: EngineSource = .winecxGPTK(tag: "runtime-v4.8.3")) -> Engine {
    Engine(
        manifest: EngineManifest(
            id: "sample", name: "Sample", source: source, d3dmetalCapable: source.d3dmetalCapable, wineRoot: "Wine"
        ),
        directory: URL(fileURLWithPath: "/engines/sample", isDirectory: true)
    )
}
