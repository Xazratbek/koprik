import Foundation

/// What public databases say about running a game outside Windows.
///
/// Both sources describe Linux with Proton. Wine on a Mac behaves the same
/// way where anti-cheat is concerned, and similarly but not identically for
/// everything else, so the rating is a hint rather than a promise.
public struct CompatibilityReport: Codable, Sendable, Equatable {
    public enum AntiCheatStatus: String, Codable, Sendable {
        /// The anti-cheat refuses Wine. The game cannot be played online.
        case denied = "Denied"
        case broken = "Broken"
        case planned = "Planned"
        case running = "Running"
        case supported = "Supported"

        public var blocksPlay: Bool { self == .denied || self == .broken }
    }

    public var appID: Int?
    public var name: String?
    /// ProtonDB tier: platinum, gold, silver, bronze, borked, or pending.
    public var protonTier: String?
    public var protonReports: Int?
    public var antiCheat: AntiCheatStatus?
    public var antiCheatNames: [String]

    public init(appID: Int? = nil, name: String? = nil, protonTier: String? = nil, protonReports: Int? = nil,
                antiCheat: AntiCheatStatus? = nil, antiCheatNames: [String] = []) {
        self.appID = appID
        self.name = name
        self.protonTier = protonTier
        self.protonReports = protonReports
        self.antiCheat = antiCheat
        self.antiCheatNames = antiCheatNames
    }

    /// True when the game is known not to work because of its anti-cheat.
    public var isBlocked: Bool { antiCheat?.blocksPlay ?? false }
}

/// Fetches and caches compatibility data.
public actor CompatibilityService {
    static let antiCheatListURL = URL(string: "https://raw.githubusercontent.com/AreWeAntiCheatYet/AreWeAntiCheatYet/master/games.json")!

    private struct AntiCheatEntry: Decodable {
        let name: String
        let status: String
        let anticheats: [String]?
        let storeIds: [String: String]?
    }

    private let paths: AppPaths
    private var antiCheatBySteamID: [Int: AntiCheatEntry]?
    private var antiCheatByName: [String: AntiCheatEntry] = [:]
    private var reports: [Int: CompatibilityReport] = [:]

    public init(paths: AppPaths = .default) {
        self.paths = paths
    }

    private var cacheDirectory: URL { paths.cache.appending(path: "compat", directoryHint: .isDirectory) }

    public func report(forSteamApp appID: Int, name: String? = nil) async -> CompatibilityReport {
        if let cached = reports[appID] { return cached }
        await loadAntiCheatList()

        var report = CompatibilityReport(appID: appID, name: name)
        if let entry = antiCheatBySteamID?[appID] ?? name.flatMap({ antiCheatByName[Self.normalize($0)] }) {
            report.antiCheat = CompatibilityReport.AntiCheatStatus(rawValue: entry.status)
            report.antiCheatNames = entry.anticheats ?? []
        }
        if let summary = await protonSummary(appID: appID) {
            report.protonTier = summary.tier
            report.protonReports = summary.total
        }
        reports[appID] = report
        return report
    }

    /// Looks a game up by name only, for programs that did not come from Steam.
    public func report(forName name: String) async -> CompatibilityReport {
        await loadAntiCheatList()
        var report = CompatibilityReport(name: name)
        if let entry = antiCheatByName[Self.normalize(name)] {
            report.antiCheat = CompatibilityReport.AntiCheatStatus(rawValue: entry.status)
            report.antiCheatNames = entry.anticheats ?? []
            report.appID = entry.storeIds?["steam"].flatMap(Int.init)
        }
        return report
    }

    // MARK: Sources

    private struct ProtonSummary: Decodable {
        let tier: String
        let total: Int?
    }

    private func protonSummary(appID: Int) async -> ProtonSummary? {
        let file = cacheDirectory.appending(path: "protondb-\(appID).json")
        if let data = freshData(at: file, maxAge: 14 * 86_400) {
            return try? JSONDecoder().decode(ProtonSummary.self, from: data)
        }
        guard let url = URL(string: "https://www.protondb.com/api/v1/reports/summaries/\(appID).json"),
              let data = await fetch(url) else { return nil }
        store(data, at: file)
        return try? JSONDecoder().decode(ProtonSummary.self, from: data)
    }

    private func loadAntiCheatList() async {
        guard antiCheatBySteamID == nil else { return }
        let file = cacheDirectory.appending(path: "anticheat.json")
        var data = freshData(at: file, maxAge: 7 * 86_400)
        if data == nil, let fetched = await fetch(Self.antiCheatListURL) {
            store(fetched, at: file)
            data = fetched
        }
        // Offline with a stale copy: still better than nothing.
        data = data ?? (try? Data(contentsOf: file))
        let entries = data.flatMap { try? JSONDecoder().decode([AntiCheatEntry].self, from: $0) } ?? []
        var bySteamID: [Int: AntiCheatEntry] = [:]
        for entry in entries {
            antiCheatByName[Self.normalize(entry.name)] = entry
            if let id = entry.storeIds?["steam"].flatMap(Int.init) { bySteamID[id] = entry }
        }
        antiCheatBySteamID = bySteamID
    }

    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private func freshData(at file: URL, maxAge: TimeInterval) -> Data? {
        guard let modified = try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date,
              Date.now.timeIntervalSince(modified) < maxAge else { return nil }
        return try? Data(contentsOf: file)
    }

    private func store(_ data: Data, at file: URL) {
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
