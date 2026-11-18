import Foundation

public enum GcenxChannel: String, Codable, Sendable, CaseIterable {
    case stable, devel, staging
}

/// Where a Wine build comes from.
public enum EngineSource: Codable, Sendable, Equatable {
    /// `frankea/winecx-gptk`: Wine rebased with CrossOver's macOS patches. The
    /// only public prebuilt engine that can host Apple's D3DMetal.
    case winecxGPTK(tag: String)
    /// `Gcenx/macOS_Wine_builds`: plain upstream Wine.
    case gcenx(channel: GcenxChannel, tag: String)
    /// Ko'prik's own build (scripts/build-engine.sh), published as a release of
    /// github.com/Xazratbek/koprik tagged `engine-v<version>`.
    case koprik(tag: String)
    /// A Wine tree or archive supplied from disk.
    case local(path: String)

    /// The engine recommended for games on Apple silicon.
    public static let recommendedGaming = EngineSource.winecxGPTK(tag: "runtime-v4.8.3")
    /// A plain Wine build for ordinary applications and as a fallback.
    public static let recommendedPlain = EngineSource.gcenx(channel: .devel, tag: "11.21")
    /// The newest Ko'prik engine known when this version was released.
    public static let knownKoprikTag = "engine-v0.1.1"

    /// The newest `engine-v*` release of Ko'prik's own engine, asked from
    /// GitHub; the known tag if GitHub cannot be reached.
    public static func latestKoprik() async -> EngineSource {
        let url = URL(string: "https://api.github.com/repos/Xazratbek/koprik/releases?per_page=30")!
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        struct Release: Decodable { let tag_name: String; let draft: Bool; let prerelease: Bool }
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let releases = try? JSONDecoder().decode([Release].self, from: data),
              let newest = releases.first(where: { $0.tag_name.hasPrefix("engine-v") && !$0.draft && !$0.prerelease })
        else { return .koprik(tag: knownKoprikTag) }
        return .koprik(tag: newest.tag_name)
    }

    public var archiveURL: URL? {
        switch self {
        case .winecxGPTK(let tag):
            URL(string: "https://github.com/frankea/winecx-gptk/releases/download/\(tag)/Libraries.tar.gz")
        case .koprik(let tag):
            URL(string: "https://github.com/Xazratbek/koprik/releases/download/\(tag)/Libraries.tar.gz")
        case .gcenx(let channel, let tag):
            URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/\(tag)/wine-\(channel.rawValue)-\(tag)-osx64.tar.xz")
        case .local:
            nil
        }
    }

    /// A `shasum`-style file published next to the archive, when the project provides one.
    public var checksumURL: URL? {
        switch self {
        case .winecxGPTK(let tag):
            URL(string: "https://github.com/frankea/winecx-gptk/releases/download/\(tag)/Libraries.tar.gz.sha256")
        case .koprik(let tag):
            URL(string: "https://github.com/Xazratbek/koprik/releases/download/\(tag)/Libraries.tar.gz.sha256")
        case .gcenx, .local:
            nil
        }
    }

    /// Hashes recorded when a release was reviewed. They take precedence over the
    /// published checksum file, which lives beside the archive and so only
    /// guards against corruption, not against a replaced release.
    public var pinnedSHA256: String? {
        switch self {
        case .winecxGPTK(tag: "runtime-v4.8.3"):
            "08ffabd7b7c352470faee2b1d51061b341316e401439ca805c5302acc2fb8818"
        case .gcenx(channel: .stable, tag: "11.0_1"):
            "b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388"
        default:
            nil
        }
    }

    public var defaultID: String {
        switch self {
        case .winecxGPTK(let tag):
            "winecx-gptk-" + tag.replacingOccurrences(of: "runtime-v", with: "")
        case .koprik(let tag):
            "koprik-" + tag.replacingOccurrences(of: "engine-v", with: "")
        case .gcenx(let channel, let tag):
            "wine-\(channel.rawValue)-\(tag)"
        case .local(let path):
            "local-" + URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
                .lowercased().replacingOccurrences(of: " ", with: "-")
        }
    }

    public var displayName: String {
        switch self {
        case .winecxGPTK(let tag):
            "Wine + CrossOver patches (\(tag.replacingOccurrences(of: "runtime-v", with: "")))"
        case .koprik(let tag):
            "Ko'prik engine \(tag.replacingOccurrences(of: "engine-v", with: ""))"
        case .gcenx(let channel, let tag):
            "Wine \(channel.rawValue) \(tag)"
        case .local(let path):
            URL(fileURLWithPath: path).lastPathComponent
        }
    }

    /// D3DMetal patches CrossOver-specific internals at load time, so it only
    /// runs on CrossOver-derived builds.
    public var d3dmetalCapable: Bool {
        switch self {
        case .winecxGPTK, .koprik: return true
        case .gcenx, .local: return false
        }
    }
}

/// The record stored as `engine.json` inside each installed engine.
public struct EngineManifest: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var source: EngineSource
    public var architecture: String
    public var d3dmetalCapable: Bool
    /// Output of `wine --version`, filled in after installation when Wine can run.
    public var wineVersion: String?
    /// Versions of bundled parts, for example `["dxmt": "0.80", "dxvk": "1.10.3"]`.
    public var components: [String: String]
    /// Path from the engine directory to the folder that contains `bin/`.
    public var wineRoot: String
    public var installedAt: Date

    public init(
        id: String,
        name: String,
        source: EngineSource,
        architecture: String = "x86_64",
        d3dmetalCapable: Bool,
        wineVersion: String? = nil,
        components: [String: String] = [:],
        wineRoot: String,
        installedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.architecture = architecture
        self.d3dmetalCapable = d3dmetalCapable
        self.wineVersion = wineVersion
        self.components = components
        self.wineRoot = wineRoot
        self.installedAt = installedAt
    }
}

/// An installed Wine build.
public struct Engine: Sendable, Equatable, Identifiable {
    public static let manifestName = "engine.json"

    public var manifest: EngineManifest
    public let directory: URL

    public init(manifest: EngineManifest, directory: URL) {
        self.manifest = manifest
        self.directory = directory
    }

    public var id: String { manifest.id }
    public var name: String { manifest.name }

    public var wineRoot: URL {
        manifest.wineRoot.isEmpty ? directory : directory.appending(path: manifest.wineRoot, directoryHint: .isDirectory)
    }

    public var binDirectory: URL { wineRoot.appending(path: "bin", directoryHint: .isDirectory) }

    /// `bin/wine64` when present, otherwise `bin/wine`. Newer builds ship only `wine`.
    public var wineBinary: URL {
        // The Game Mode bundle's loader when it exists (see GameBundle).
        if let loader = GameBundle.loader(for: self) { return loader }
        let wine64 = binDirectory.appending(path: "wine64")
        return FileManager.default.isExecutableFile(atPath: wine64.path) ? wine64 : binDirectory.appending(path: "wine")
    }

    public var wineserverBinary: URL { binDirectory.appending(path: "wineserver") }

    /// Settings that suit this engine before any bottle or program overrides.
    public var defaultSettings: LaunchSettings {
        var settings = LaunchSettings()
        // MSync is a CrossOver patch; upstream Wine does not have it.
        switch manifest.source {
        case .winecxGPTK, .koprik: settings.sync = .msync
        case .gcenx, .local: break
        }
        return settings
    }
}
