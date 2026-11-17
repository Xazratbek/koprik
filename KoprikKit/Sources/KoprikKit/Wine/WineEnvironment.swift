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
        "WINED3DMETAL", "MTL_DEBUG_LAYER", "DXMT_CONFIG", "DXMT_METALFX_SPATIAL_SWAPCHAIN", "DXVK_CONFIG_FILE",
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
        // GStreamer otherwise floods the log with warnings from codecs it probes.
        environment["GST_DEBUG"] = "1"
        // Chromium's sandbox cannot work inside Wine; without these the Steam
        // client's web views (store, library, login) stay blank.
        environment["STEAM_DISABLE_CEF_SANDBOX"] = "1"
        environment["CEF_DISABLE_SANDBOX"] = "1"
        environment["STEAM_RUNTIME"] = "0"
        // Metal's validation layer costs frame time and is only useful to developers.
        environment["MTL_DEBUG_LAYER"] = "0"
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
        // Wine's powershell.exe is a stub that does nothing and exits 0. The
        // installers electron-builder makes (Notion, Discord, Slack, ...) ask
        // PowerShell whether the app is running; the stub's 0 means "yes", so
        // they stop with "<App> is running" and never install. Disabled, the
        // call fails the way it would on a PC without PowerShell. A user
        // override for powershell.exe still wins.
        overrides["powershell.exe"] = "d"
        overrides.merge(settings.dllOverrides ?? [:]) { _, user in user }
        if !overrides.isEmpty {
            environment["WINEDLLOVERRIDES"] = dllOverridesString(overrides)
        }

        switch settings.backend ?? .auto {
        case .wined3d:
            // Keeps a D3DMetal-enabled engine on Wine's own Direct3D.
            environment["WINED3DMETAL"] = "0"
        case .dxvk:
            // Lets MoltenVK compile shaders on all cores, which shortens stutter.
            environment["MVK_CONFIG_SHOULD_MAXIMIZE_CONCURRENT_COMPILATION"] = "1"
        case .auto, .d3dmetal, .dxmt:
            break
        }

        // DXMT reads `key = value` pairs separated by ";" from DXMT_CONFIG.
        var dxmtConfig: [String] = []
        if let rate = settings.maxFrameRate, rate > 0 {
            dxmtConfig.append("d3d11.preferredMaxFrameRate = \(rate)")
        }
        if let factor = settings.metalFXUpscale, factor > 1 {
            dxmtConfig.append("d3d11.metalSpatialUpscaleFactor = \(factor)")
            environment["DXMT_METALFX_SPATIAL_SWAPCHAIN"] = "1"
        }
        if !dxmtConfig.isEmpty { environment["DXMT_CONFIG"] = dxmtConfig.joined(separator: ";") }

        if settings.metalHUD == true { environment["MTL_HUD_ENABLED"] = "1" }
        if let hud = settings.dxvkHUD?.environmentValue { environment["DXVK_HUD"] = hud }
        if settings.dxvkAsync == true { environment["DXVK_ASYNC"] = "1" }
        if settings.advertiseAVX == true { environment["ROSETTA_ADVERTISE_AVX"] = "1" }
        if settings.raytracing == true { environment["D3DM_SUPPORT_DXR"] = "1" }
        // Wine takes the Windows locale, and with it the ANSI code page, from the Unix locale.
        if let language = settings.language, !language.isEmpty {
            environment["LANG"] = "\(language).UTF-8"
            environment["LC_ALL"] = "\(language).UTF-8"
        }

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
    /// The DLLs themselves are put in place by `Graphics.prepare`.
    static func backendOverrides(for backend: GraphicsBackend) -> [String: String] {
        switch backend {
        case .dxvk:
            ["dxgi": "n,b", "d3d9": "n,b", "d3d10core": "n,b", "d3d11": "n,b"]
        case .dxmt:
            // winemetal is DXMT's bridge to Metal and ships inside the engine.
            ["dxgi": "n,b", "d3d10core": "n,b", "d3d11": "n,b", "winemetal": "b"]
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
