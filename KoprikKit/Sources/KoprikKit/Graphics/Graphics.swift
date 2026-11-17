import Foundation

/// Which Direct3D translation layers an engine can offer.
public struct GraphicsCapabilities: Sendable, Equatable {
    public var dxmt: Bool
    public var dxvk: Bool
    public var d3dmetal: Bool

    public func supports(_ backend: GraphicsBackend) -> Bool {
        switch backend {
        case .auto, .wined3d: true
        case .dxmt: dxmt
        case .dxvk: dxvk
        case .d3dmetal: d3dmetal
        }
    }
}

/// A backend choice together with the reason for it, so the interface can
/// explain what "Auto" did.
public struct GraphicsDecision: Sendable, Equatable {
    public var backend: GraphicsBackend
    public var reason: String
}

/// Selects a Direct3D backend and makes a bottle ready for it.
///
/// How switching works on a winecx-gptk engine (confirmed against the engine
/// and against Whisky's source):
/// - DXMT and DXVK are ordinary Windows DLLs. They are copied into the
///   bottle's `system32`/`syswow64` and chosen with `WINEDLLOVERRIDES`.
/// - D3DMetal lives in the engine itself, once Apple's Game Porting Toolkit
///   has been imported: its DLLs replace Wine's builtin Direct3D DLLs.
/// - wined3d is Wine's own implementation, reached by leaving the builtin
///   DLLs in place and setting `WINED3DMETAL=0`.
///
/// Both DXMT and DXVK use the file names `d3d11.dll` and `d3d10core.dll`, so
/// a bottle holds one of them at a time; `prepare` swaps them before a launch.
public enum Graphics {
    /// Every file name a backend may place in the bottle.
    static let managedNames = ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll", "winemetal.dll", "nvapi64.dll", "nvngx.dll"]

    private static func componentDirectory(_ name: String, in engine: Engine) -> URL {
        engine.wineRoot.deletingLastPathComponent().appending(path: name, directoryHint: .isDirectory)
    }

    public static func capabilities(of engine: Engine) -> GraphicsCapabilities {
        let manager = FileManager.default
        func has(_ component: String) -> Bool {
            manager.fileExists(atPath: componentDirectory(component, in: engine).appending(path: "x64/d3d11.dll").path)
        }
        let external = engine.wineRoot.appending(path: "lib/external", directoryHint: .isDirectory)
        return GraphicsCapabilities(
            dxmt: has("DXMT"),
            dxvk: has("DXVK"),
            d3dmetal: manager.fileExists(atPath: external.appending(path: "libd3dshared.dylib").path)
                && manager.fileExists(atPath: external.appending(path: "D3DMetal.framework").path)
        )
    }

    /// Turns the user's choice into a concrete backend.
    ///
    /// For `auto` the decision follows the Direct3D version the program
    /// imports. `executables` may list several files (a game folder often has
    /// a small launcher beside the real binary); the newest API found wins.
    public static func decide(
        requested: GraphicsBackend?,
        engine: Engine,
        executables: [URL]
    ) -> GraphicsDecision {
        let capabilities = capabilities(of: engine)
        if let requested, requested != .auto {
            if capabilities.supports(requested) {
                return GraphicsDecision(backend: requested, reason: "Chosen in settings.")
            }
            let fallback = decide(requested: .auto, engine: engine, executables: executables)
            return GraphicsDecision(
                backend: fallback.backend,
                reason: "\(requested.displayName) is not available in this engine. \(fallback.reason)"
            )
        }

        var imports: Set<String> = []
        for executable in executables {
            imports.formUnion(PEFile(url: executable)?.importedLibraries ?? [])
        }
        let usesD3D12 = imports.contains("d3d12.dll")
        let usesD3D11 = !imports.isDisjoint(with: ["d3d11.dll", "d3d10.dll", "d3d10_1.dll", "dxgi.dll"])
        let usesOld = !imports.isDisjoint(with: ["d3d9.dll", "d3d8.dll", "ddraw.dll", "opengl32.dll"])

        if usesD3D12 {
            if capabilities.d3dmetal {
                return GraphicsDecision(backend: .d3dmetal, reason: "The program uses Direct3D 12, which D3DMetal handles.")
            }
            if capabilities.dxmt, usesD3D11 {
                return GraphicsDecision(backend: .dxmt, reason: "The program can use Direct3D 11. Direct3D 12 needs the Game Porting Toolkit, which is not imported.")
            }
            return GraphicsDecision(backend: .wined3d, reason: "The program uses Direct3D 12. Import the Game Porting Toolkit for it to run well.")
        }
        if usesD3D11, !usesOld || imports.contains("d3d11.dll") {
            if capabilities.dxmt {
                return GraphicsDecision(backend: .dxmt, reason: "The program uses Direct3D 10/11, which DXMT translates to Metal.")
            }
            if capabilities.d3dmetal {
                return GraphicsDecision(backend: .d3dmetal, reason: "The program uses Direct3D 10/11.")
            }
            if capabilities.dxvk {
                return GraphicsDecision(backend: .dxvk, reason: "The program uses Direct3D 10/11.")
            }
        }
        if usesOld {
            return GraphicsDecision(backend: .wined3d, reason: "The program uses Direct3D 9 or older, or OpenGL, which Wine handles itself.")
        }
        // Nothing recognisable in the import table: launchers, .NET programs and
        // engines that load Direct3D at run time. DXMT covers the common case.
        if capabilities.dxmt {
            return GraphicsDecision(backend: .dxmt, reason: "No Direct3D version found in the program file, so the most widely compatible backend is used.")
        }
        return GraphicsDecision(backend: .wined3d, reason: "No other backend is available in this engine.")
    }

    /// Puts the backend's DLLs into the bottle and restores Wine's own copies
    /// of every managed file the backend does not provide.
    ///
    /// Files are only rewritten when their content differs, so repeated
    /// launches cost a few stat calls.
    public static func prepare(_ backend: GraphicsBackend, engine: Engine, prefix: URL) throws {
        let component: URL? = switch backend {
        case .dxmt: componentDirectory("DXMT", in: engine)
        case .dxvk: componentDirectory("DXVK", in: engine)
        case .auto, .d3dmetal, .wined3d: nil
        }
        let windows = prefix.appending(path: "drive_c/windows", directoryHint: .isDirectory)
        let targets: [(payload: String, builtin: String, destination: URL)] = [
            ("x64", "x86_64-windows", windows.appending(path: "system32", directoryHint: .isDirectory)),
            ("x32", "i386-windows", windows.appending(path: "syswow64", directoryHint: .isDirectory)),
        ]
        let manager = FileManager.default
        for target in targets where manager.fileExists(atPath: target.destination.path) {
            for name in managedNames {
                let destination = target.destination.appending(path: name)
                let fromBackend = component?.appending(path: "\(target.payload)/\(name)")
                let fromEngine = engine.wineRoot.appending(path: "lib/wine/\(target.builtin)/\(name)")

                if let fromBackend, manager.fileExists(atPath: fromBackend.path) {
                    try install(fromBackend, at: destination)
                } else if manager.fileExists(atPath: fromEngine.path) {
                    try install(fromEngine, at: destination)
                } else if manager.fileExists(atPath: destination.path) {
                    // A leftover from another backend with no builtin counterpart.
                    try manager.removeItem(at: destination)
                }
            }
        }
    }

    private static func install(_ source: URL, at destination: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destination.path) {
            if manager.contentsEqual(atPath: source.path, andPath: destination.path) { return }
            try manager.removeItem(at: destination)
        }
        try manager.copyItem(at: source, to: destination)
    }
}

extension GraphicsBackend {
    public var displayName: String {
        switch self {
        case .auto: "Auto"
        case .d3dmetal: "D3DMetal"
        case .dxmt: "DXMT"
        case .dxvk: "DXVK"
        case .wined3d: "wined3d"
        }
    }
}

extension Graphics {
    /// Records which files `prepareLocal` placed in a folder, so they can be
    /// told apart from DLLs the program ships itself.
    static let localMarkerName = ".koprik-graphics"

    /// Puts a backend's DLLs next to a program, for when the bottle's shared
    /// `system32` has to stay on another backend. Files the program ships
    /// itself are never replaced.
    public static func prepareLocal(_ backend: GraphicsBackend, engine: Engine, directory: URL) throws {
        try clearLocal(in: directory)
        let component: URL? = switch backend {
        case .dxmt: engine.wineRoot.deletingLastPathComponent().appending(path: "DXMT/x64", directoryHint: .isDirectory)
        case .dxvk: engine.wineRoot.deletingLastPathComponent().appending(path: "DXVK/x64", directoryHint: .isDirectory)
        // The engine's own DLLs are what Wine falls back to anyway.
        case .wined3d, .d3dmetal, .auto: engine.wineRoot.appending(path: "lib/wine/x86_64-windows", directoryHint: .isDirectory)
        }
        guard let component else { return }
        let manager = FileManager.default
        var placed: [String] = []
        // winemetal is the engine's bridge to Metal; the builtin copy in system32 is the one that matches it.
        for name in ["d3d9.dll", "d3d10core.dll", "d3d11.dll", "dxgi.dll"] {
            let source = component.appending(path: name)
            let destination = directory.appending(path: name)
            guard manager.fileExists(atPath: source.path), !manager.fileExists(atPath: destination.path) else { continue }
            try manager.copyItem(at: source, to: destination)
            placed.append(name)
        }
        if !placed.isEmpty {
            try placed.joined(separator: "\n").write(to: directory.appending(path: localMarkerName), atomically: true, encoding: .utf8)
        }
    }

    /// Removes the DLLs `prepareLocal` placed, and only those.
    public static func clearLocal(in directory: URL) throws {
        let marker = directory.appending(path: localMarkerName)
        guard let list = try? String(contentsOf: marker, encoding: .utf8) else { return }
        for name in list.split(separator: "\n") where !name.contains("/") {
            try? FileManager.default.removeItem(at: directory.appending(path: String(name)))
        }
        try FileManager.default.removeItem(at: marker)
    }
}
