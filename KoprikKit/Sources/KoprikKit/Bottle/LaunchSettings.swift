import Foundation

public enum WindowsVersion: String, Codable, Sendable, CaseIterable {
    case win7, win8, win81, win10, win11

    public var displayName: String {
        switch self {
        case .win7: "Windows 7"
        case .win8: "Windows 8"
        case .win81: "Windows 8.1"
        case .win10: "Windows 10"
        case .win11: "Windows 11"
        }
    }
}

public enum GraphicsBackend: String, Codable, Sendable, CaseIterable {
    /// Leave the choice to the engine (and, later, to per-game rules).
    case auto
    /// Apple's Direct3D 11/12 to Metal layer from the Game Porting Toolkit.
    case d3dmetal
    /// Direct3D 10/11 to Metal.
    case dxmt
    /// Direct3D 9/10/11 to Vulkan, over MoltenVK.
    case dxvk
    /// Wine's own Direct3D implementation.
    case wined3d
}

public enum SyncMode: String, Codable, Sendable, CaseIterable {
    case none, esync, msync
}

public enum DXVKHud: String, Codable, Sendable, CaseIterable {
    case off, fps, partial, full

    var environmentValue: String? {
        switch self {
        case .off: nil
        case .fps: "fps"
        case .partial: "devinfo,fps,frametimes"
        case .full: "full"
        }
    }
}

/// Options that shape how a Windows program is started.
///
/// Every field is optional so that settings can be stacked: engine defaults,
/// then the bottle, then the individual program, then a one-off run. A layer
/// only overrides what it actually sets.
public struct LaunchSettings: Codable, Sendable, Equatable {
    public var backend: GraphicsBackend?
    public var sync: SyncMode?
    public var metalHUD: Bool?
    public var dxvkHUD: DXVKHud?
    public var dxvkAsync: Bool?
    /// Tell programs that AVX is available under Rosetta.
    public var advertiseAVX: Bool?
    /// Enable DirectX Raytracing in D3DMetal.
    public var raytracing: Bool?
    /// Extra environment variables. Applied last, so they win over everything above.
    public var environment: [String: String]?
    /// DLL load order, for example `["d3dcompiler_47": "n,b"]`.
    public var dllOverrides: [String: String]?
    /// Frame rate cap for DXMT and DXVK. 0 removes a cap set lower down.
    public var maxFrameRate: Int?
    /// DXMT only: render at 1/factor of the window size and let MetalFX
    /// upscale, for example 1.5 or 2. Raises frame rate in GPU-bound games.
    public var metalFXUpscale: Double?

    public init(
        backend: GraphicsBackend? = nil,
        sync: SyncMode? = nil,
        metalHUD: Bool? = nil,
        dxvkHUD: DXVKHud? = nil,
        dxvkAsync: Bool? = nil,
        advertiseAVX: Bool? = nil,
        raytracing: Bool? = nil,
        environment: [String: String]? = nil,
        dllOverrides: [String: String]? = nil,
        maxFrameRate: Int? = nil,
        metalFXUpscale: Double? = nil
    ) {
        self.backend = backend
        self.sync = sync
        self.metalHUD = metalHUD
        self.dxvkHUD = dxvkHUD
        self.dxvkAsync = dxvkAsync
        self.advertiseAVX = advertiseAVX
        self.raytracing = raytracing
        self.environment = environment
        self.dllOverrides = dllOverrides
        self.maxFrameRate = maxFrameRate
        self.metalFXUpscale = metalFXUpscale
    }

    /// Returns these settings with `other` laid on top. Scalar fields are
    /// replaced when `other` sets them; dictionaries are merged key by key.
    public func merging(_ other: LaunchSettings) -> LaunchSettings {
        LaunchSettings(
            backend: other.backend ?? backend,
            sync: other.sync ?? sync,
            metalHUD: other.metalHUD ?? metalHUD,
            dxvkHUD: other.dxvkHUD ?? dxvkHUD,
            dxvkAsync: other.dxvkAsync ?? dxvkAsync,
            advertiseAVX: other.advertiseAVX ?? advertiseAVX,
            raytracing: other.raytracing ?? raytracing,
            environment: Self.merge(environment, other.environment),
            dllOverrides: Self.merge(dllOverrides, other.dllOverrides),
            maxFrameRate: other.maxFrameRate ?? maxFrameRate,
            metalFXUpscale: other.metalFXUpscale ?? metalFXUpscale
        )
    }

    /// Stacks layers from lowest to highest priority.
    public static func resolve(_ layers: [LaunchSettings]) -> LaunchSettings {
        layers.reduce(LaunchSettings()) { $0.merging($1) }
    }

    private static func merge(_ base: [String: String]?, _ top: [String: String]?) -> [String: String]? {
        guard base != nil || top != nil else { return nil }
        return (base ?? [:]).merging(top ?? [:]) { _, new in new }
    }
}
