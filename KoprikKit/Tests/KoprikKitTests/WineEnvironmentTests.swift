import Foundation
import Testing
@testable import KoprikKit

@Suite struct WineEnvironmentTests {
    let prefix = URL(fileURLWithPath: "/bottles/b/prefix", isDirectory: true)
    let host = ["PATH": "/usr/bin:/bin", "HOME": "/Users/me"]

    private func build(_ settings: LaunchSettings, engine: Engine = sampleEngine(), host: [String: String]? = nil) -> [String: String] {
        WineEnvironment.build(engine: engine, prefix: prefix, settings: settings, host: host ?? self.host)
    }

    @Test func setsPrefixDebugLevelAndPutsEngineFirstOnPath() {
        let environment = build(LaunchSettings())
        #expect(environment["WINEPREFIX"] == "/bottles/b/prefix")
        #expect(environment["WINEDEBUG"] == "fixme-all")
        #expect(environment["PATH"] == "/engines/sample/Wine/bin:/usr/bin:/bin")
        #expect(environment["HOME"] == "/Users/me")
    }

    @Test func plainSettingsAddNoTuningVariables() {
        let environment = build(LaunchSettings())
        for key in ["WINEESYNC", "WINEMSYNC", "WINEDLLOVERRIDES", "MTL_HUD_ENABLED", "DXVK_HUD", "D3DM_SUPPORT_DXR"] {
            #expect(environment[key] == nil, "\(key) should be unset")
        }
    }

    @Test func msyncAlsoSetsEsyncBecauseD3DMetalChecksIt() {
        let environment = build(LaunchSettings(sync: .msync))
        #expect(environment["WINEMSYNC"] == "1")
        #expect(environment["WINEESYNC"] == "1")
    }

    @Test func esyncAloneDoesNotSetMsync() {
        let environment = build(LaunchSettings(sync: .esync))
        #expect(environment["WINEESYNC"] == "1")
        #expect(environment["WINEMSYNC"] == nil)
    }

    @Test func dxvkAndDxmtRouteDirect3DThroughDllOverrides() {
        #expect(build(LaunchSettings(backend: .dxvk))["WINEDLLOVERRIDES"] == "d3d10core,d3d11,d3d9,dxgi=n,b")
        #expect(build(LaunchSettings(backend: .dxmt))["WINEDLLOVERRIDES"] == "d3d10core,d3d11,dxgi=n,b")
        #expect(build(LaunchSettings(backend: .d3dmetal))["WINEDLLOVERRIDES"] == nil)
    }

    @Test func userDllOverridesWinAndAreGroupedByLoadOrder() {
        let settings = LaunchSettings(backend: .dxmt, dllOverrides: ["dxgi": "b", "mscoree": "d"])
        #expect(build(settings)["WINEDLLOVERRIDES"] == "d3d10core,d3d11=n,b;dxgi=b;mscoree=d")
    }

    @Test func togglesMapToTheirVariables() {
        let environment = build(LaunchSettings(
            metalHUD: true, dxvkHUD: .partial, dxvkAsync: true, advertiseAVX: true, raytracing: true
        ))
        #expect(environment["MTL_HUD_ENABLED"] == "1")
        #expect(environment["DXVK_HUD"] == "devinfo,fps,frametimes")
        #expect(environment["DXVK_ASYNC"] == "1")
        #expect(environment["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(environment["D3DM_SUPPORT_DXR"] == "1")
    }

    @Test func hudOffAndFalseTogglesStayUnset() {
        let environment = build(LaunchSettings(metalHUD: false, dxvkHUD: .off, raytracing: false))
        #expect(environment["MTL_HUD_ENABLED"] == nil)
        #expect(environment["DXVK_HUD"] == nil)
        #expect(environment["D3DM_SUPPORT_DXR"] == nil)
    }

    @Test func userEnvironmentOverridesEveryRule() {
        let settings = LaunchSettings(sync: .msync, environment: ["WINEDEBUG": "+seh", "WINEMSYNC": "0", "MY_FLAG": "x"])
        let environment = build(settings)
        #expect(environment["WINEDEBUG"] == "+seh")
        #expect(environment["WINEMSYNC"] == "0")
        #expect(environment["MY_FLAG"] == "x")
    }

    @Test func hostWineVariablesAreNotInherited() {
        let polluted = host.merging(["WINEPREFIX": "/elsewhere", "WINEDLLOVERRIDES": "x=n", "WINEESYNC": "1", "DXVK_HUD": "full"]) { $1 }
        let environment = build(LaunchSettings(), host: polluted)
        #expect(environment["WINEPREFIX"] == "/bottles/b/prefix")
        #expect(environment["WINEDLLOVERRIDES"] == nil)
        #expect(environment["WINEESYNC"] == nil)
        #expect(environment["DXVK_HUD"] == nil)
    }

    @Test func shellExportsQuoteValuesAndCanBeFiltered() {
        let text = WineEnvironment.shellExports(["B": "it's", "A": "1", "C": "skip"], onlyKeys: ["A", "B"])
        #expect(text == "export A='1'\nexport B='it'\\''s'")
    }
}

@Suite struct LaunchSettingsTests {
    @Test func laterLayersOverrideOnlyWhatTheySet() {
        let resolved = LaunchSettings.resolve([
            LaunchSettings(backend: .dxmt, sync: .msync, metalHUD: false),
            LaunchSettings(backend: .d3dmetal),
            LaunchSettings(metalHUD: true),
        ])
        #expect(resolved.backend == .d3dmetal)
        #expect(resolved.sync == .msync)
        #expect(resolved.metalHUD == true)
    }

    @Test func dictionariesMergeKeyByKey() {
        let resolved = LaunchSettings.resolve([
            LaunchSettings(environment: ["A": "1", "B": "1"], dllOverrides: ["x": "n"]),
            LaunchSettings(environment: ["B": "2"]),
        ])
        #expect(resolved.environment == ["A": "1", "B": "2"])
        #expect(resolved.dllOverrides == ["x": "n"])
    }

    @Test func emptyLayersLeaveDictionariesNil() {
        #expect(LaunchSettings.resolve([LaunchSettings(), LaunchSettings()]).environment == nil)
    }

    @Test func onlyCrossOverDerivedEnginesDefaultToMsync() {
        #expect(sampleEngine(source: .winecxGPTK(tag: "runtime-v4.8.3")).defaultSettings.sync == .msync)
        #expect(sampleEngine(source: .gcenx(channel: .devel, tag: "11.21")).defaultSettings.sync == nil)
    }

    @Test func surviveAJSONRoundTrip() throws {
        let original = LaunchSettings(backend: .dxvk, sync: .esync, dxvkHUD: .fps, environment: ["K": "V"])
        let decoded = try JSONDecoder().decode(LaunchSettings.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }
}
