import Foundation

/// Builds the environment a Wine process starts with.
///
/// This is a pure function of its inputs so that every rule can be unit-tested
/// without launching Wine.
public enum WineEnvironment {
    /// Host variables that would redirect Wine away from the engine or bottle we chose.
    private static let scrubbedKeys: Set<String> = [
        "WINEPREFIX", "WINEARCH", "WINELOADER", "WINESERVER", "WINEDLLPATH",
        "WINEDLLOVERRIDES", "WINEDEBUG", "WINEESYNC", "WINEMSYNC", "WINEFSYNC",
        "DXVK_HUD", "DXVK_ASYNC", "MTL_HUD_ENABLED", "ROSETTA_ADVERTISE_AVX", "D3DM_SUPPORT_DXR",
    ]

    public static func build(
        engine: Engine,
        prefix: URL,
        settings: LaunchSettings,
        host: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = host.filter { !scrubbedKeys.contains($0.key) }

        environment["WINEPREFIX"] = prefix.path
        // Wine prints a "fixme" line for every unimplemented call; silencing them keeps logs readable and Wine faster.
        environment["WINEDEBUG"] = "fixme-all"
        environment["PATH"] = engine.binDirectory.path + ":" + (host["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        switch settings.sync ?? SyncMode.none {
        case .none:
            break
        case .esync:
            environment["WINEESYNC"] = "1"
        case .msync:
            environment["WINEMSYNC"] = "1"
            // D3DMetal looks for the ESync flag, so it has to accompany MSync.
            environment["WINEESYNC"] = "1"
        }

        var overrides = backendOverrides(for: settings.backend ?? .auto)
        overrides.merge(settings.dllOverrides ?? [:]) { _, user in user }
        if !overrides.isEmpty {
            environment["WINEDLLOVERRIDES"] = dllOverridesString(overrides)
        }

        if settings.metalHUD == true { environment["MTL_HUD_ENABLED"] = "1" }
        if let hud = settings.dxvkHUD?.environmentValue { environment["DXVK_HUD"] = hud }
        if settings.dxvkAsync == true { environment["DXVK_ASYNC"] = "1" }
        if settings.advertiseAVX == true { environment["ROSETTA_ADVERTISE_AVX"] = "1" }
        if settings.raytracing == true { environment["D3DM_SUPPORT_DXR"] = "1" }

        // The user's own variables come last so they can override any rule above.
        environment.merge(settings.environment ?? [:]) { _, user in user }
        return environment
    }

    /// DLL overrides that route Direct3D to the chosen translation layer.
    ///
    /// `n,b` means "prefer the native DLL placed in the prefix, fall back to
    /// Wine's builtin". D3DMetal and wined3d need no override because they are
    /// what the engine's builtin DLLs already provide.
    ///
    /// Provisional: how a winecx-gptk engine chooses between its builtin DXMT and
    /// an imported D3DMetal still has to be confirmed against a real engine
    /// (phase 1 go/no-go test 5).
    static func backendOverrides(for backend: GraphicsBackend) -> [String: String] {
        switch backend {
        case .dxvk:
            ["dxgi": "n,b", "d3d9": "n,b", "d3d10core": "n,b", "d3d11": "n,b"]
        case .dxmt:
            ["dxgi": "n,b", "d3d10core": "n,b", "d3d11": "n,b"]
        case .auto, .d3dmetal, .wined3d:
            [:]
        }
    }

    /// Formats overrides the way Wine expects: DLLs that share a load order are
    /// grouped, groups are separated by `;`. Sorted so the result is stable.
    static func dllOverridesString(_ overrides: [String: String]) -> String {
        Dictionary(grouping: overrides.keys, by: { overrides[$0]! })
            .map { mode, dlls in (dlls.sorted().joined(separator: ","), mode) }
            .sorted { $0.0 < $1.0 }
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: ";")
    }

    /// Renders an environment as `export` lines for pasting into a shell.
    public static func shellExports(_ environment: [String: String], onlyKeys: Set<String>? = nil) -> String {
        environment
            .filter { onlyKeys?.contains($0.key) ?? true }
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)='\($0.value.replacingOccurrences(of: "'", with: "'\\''"))'" }
            .joined(separator: "\n")
    }
}
