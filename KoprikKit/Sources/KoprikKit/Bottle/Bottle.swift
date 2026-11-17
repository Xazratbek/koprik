import Foundation

/// The record stored as `bottle.json` inside each bottle.
public struct BottleConfig: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    /// The engine this bottle runs on. Pinned so that installing a newer engine
    /// never changes a bottle that already works.
    public var engineID: String
    public var windowsVersion: WindowsVersion
    public var notes: String
    public var settings: LaunchSettings
    public var createdAt: Date
    /// Full-screen games take over the display ("Direct" in the Metal HUD)
    /// instead of drawing into a window the compositor redraws. Saves a
    /// frame of input latency and was worth 30-55 to 90-115 FPS in
    /// Brawlhalla. `nil` means on. Off suits programs that switch away often.
    public var exclusiveFullscreen: Bool?
    /// Walls the bottle off from the Mac. `nil` means off.
    public var isolation: Isolation?
    /// Draw at the display's full Retina resolution with 200% Windows scaling,
    /// so text is sharp instead of a 1x image stretched 2x. `nil` means on.
    public var highResolution: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        engineID: String,
        windowsVersion: WindowsVersion = .win10,
        notes: String = "",
        settings: LaunchSettings = LaunchSettings(),
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.engineID = engineID
        self.windowsVersion = windowsVersion
        self.notes = notes
        self.settings = settings
        self.createdAt = createdAt
    }
}

/// A self-contained Windows environment: its own C: drive, registry and programs.
public struct Bottle: Sendable, Equatable, Identifiable {
    public static let configName = "bottle.json"

    public var config: BottleConfig
    public let directory: URL

    public init(config: BottleConfig, directory: URL) {
        self.config = config
        self.directory = directory
    }

    public var id: UUID { config.id }
    public var name: String { config.name }

    /// The Wine prefix. Kept in a subfolder so that settings, logs and snapshots
    /// sit beside it rather than inside the Windows file tree.
    public var prefix: URL { directory.appending(path: "prefix", directoryHint: .isDirectory) }
    public var driveC: URL { prefix.appending(path: "drive_c", directoryHint: .isDirectory) }
    public var logs: URL { directory.appending(path: "logs", directoryHint: .isDirectory) }
    public var snapshots: URL { directory.appending(path: "snapshots", directoryHint: .isDirectory) }
    public var programs: URL { directory.appending(path: "programs", directoryHint: .isDirectory) }

    /// A fresh log file path for one run, named by time and purpose.
    public func newLogURL(label: String) -> URL {
        let stamp = Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "-")
        let safeLabel = label.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        return logs.appending(path: "\(stamp)-\(String(safeLabel)).log")
    }
}

/// A saved copy of a bottle's prefix that it can be rolled back to.
public struct BottleSnapshot: Codable, Sendable, Equatable, Identifiable {
    public static let infoName = "snapshot.json"

    public var id: String
    public var label: String
    public var createdAt: Date

    public init(id: String, label: String, createdAt: Date = .now) {
        self.id = id
        self.label = label
        self.createdAt = createdAt
    }
}
