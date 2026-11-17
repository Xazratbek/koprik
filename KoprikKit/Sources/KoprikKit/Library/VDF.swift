import Foundation

/// Valve's text key-value format, used by Steam for `libraryfolders.vdf` and
/// `appmanifest_*.acf`.
public indirect enum VDFValue: Sendable, Equatable {
    case string(String)
    case object([String: VDFValue])

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var object: [String: VDFValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    /// Looks a key up without regard to case, as Steam itself does.
    public subscript(key: String) -> VDFValue? {
        guard let object else { return nil }
        if let exact = object[key] { return exact }
        let lowered = key.lowercased()
        return object.first { $0.key.lowercased() == lowered }?.value
    }

    /// Parses a document. The result is an object holding the top-level keys.
    public static func parse(_ text: String) -> VDFValue {
        var scanner = Scanner(characters: Array(text))
        return .object(scanner.parseObject(topLevel: true))
    }

    private struct Scanner {
        let characters: [Character]
        var position = 0

        mutating func parseObject(topLevel: Bool) -> [String: VDFValue] {
            var result: [String: VDFValue] = [:]
            while let token = nextToken() {
                switch token {
                case .close:
                    return result
                case .open:
                    continue
                case .text(let key):
                    guard let value = nextToken() else { return result }
                    switch value {
                    case .text(let string): result[key] = .string(string)
                    case .open: result[key] = .object(parseObject(topLevel: false))
                    case .close: return result
                    }
                }
            }
            return result
        }

        enum Token {
            case text(String), open, close
        }

        mutating func nextToken() -> Token? {
            while position < characters.count {
                let character = characters[position]
                if character.isWhitespace {
                    position += 1
                } else if character == "/", position + 1 < characters.count, characters[position + 1] == "/" {
                    while position < characters.count, !characters[position].isNewline { position += 1 }
                } else {
                    break
                }
            }
            guard position < characters.count else { return nil }

            let character = characters[position]
            if character == "{" { position += 1; return .open }
            if character == "}" { position += 1; return .close }

            var text = ""
            if character == "\"" {
                position += 1
                while position < characters.count, characters[position] != "\"" {
                    if characters[position] == "\\", position + 1 < characters.count {
                        position += 1
                        switch characters[position] {
                        case "n": text.append("\n")
                        case "t": text.append("\t")
                        default: text.append(characters[position])
                        }
                    } else {
                        text.append(characters[position])
                    }
                    position += 1
                }
                position += 1
            } else {
                while position < characters.count,
                      !characters[position].isWhitespace, !"{}\"".contains(characters[position]) {
                    text.append(characters[position])
                    position += 1
                }
            }
            return .text(text)
        }
    }
}

/// A game or tool that the Windows Steam client has installed in a bottle.
public struct SteamApp: Sendable, Equatable, Identifiable {
    public var appID: Int
    public var name: String
    public var installDirectory: URL
    public var sizeOnDisk: Int64
    /// False while Steam is still downloading or updating the app.
    public var isFullyInstalled: Bool

    public var id: Int { appID }

    /// The header image Steam's store shows for the app.
    public var headerImageURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }

    /// The tall cover used in Steam's library grid.
    public var coverImageURL: URL? {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")
    }
}

/// Finds the Windows Steam client in a bottle and reads what it has installed.
public enum SteamLibrary {
    /// Shared runtime packages that Steam lists like games but nobody launches.
    private static let toolAppIDs: Set<Int> = [228980, 1070560, 1391110, 1628350, 1493710, 2180100]

    public static func steamDirectory(in bottle: Bottle) -> URL? {
        let candidates = ["Program Files (x86)/Steam", "Program Files/Steam"]
        return candidates
            .map { bottle.driveC.appending(path: $0, directoryHint: .isDirectory) }
            .first { FileManager.default.fileExists(atPath: $0.appending(path: "steam.exe").path) }
    }

    public static func isInstalled(in bottle: Bottle) -> Bool {
        steamDirectory(in: bottle) != nil
    }

    /// Every library folder Steam knows about, including the default one.
    public static func libraryFolders(in bottle: Bottle) -> [URL] {
        guard let steam = steamDirectory(in: bottle) else { return [] }
        var folders = [steam]
        let index = steam.appending(path: "steamapps/libraryfolders.vdf")
        if let text = try? String(contentsOf: index, encoding: .utf8),
           let entries = VDFValue.parse(text)["libraryfolders"]?.object {
            for entry in entries.values {
                guard let path = entry["path"]?.string,
                      let url = WindowsPath.hostURL(for: path, prefix: bottle.prefix) else { continue }
                if !folders.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) {
                    folders.append(url)
                }
            }
        }
        return folders
    }

    public static func apps(in bottle: Bottle) -> [SteamApp] {
        let manager = FileManager.default
        var apps: [SteamApp] = []
        for folder in libraryFolders(in: bottle) {
            let steamapps = folder.appending(path: "steamapps", directoryHint: .isDirectory)
            let files = (try? manager.contentsOfDirectory(at: steamapps, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("appmanifest_") && file.pathExtension == "acf" {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      let app = parseManifest(text, steamapps: steamapps),
                      !toolAppIDs.contains(app.appID) else { continue }
                apps.append(app)
            }
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func parseManifest(_ text: String, steamapps: URL) -> SteamApp? {
        guard let state = VDFValue.parse(text)["AppState"],
              let appID = state["appid"]?.string.flatMap(Int.init),
              let name = state["name"]?.string,
              let installDirectory = state["installdir"]?.string else { return nil }
        let flags = state["StateFlags"]?.string.flatMap(Int.init) ?? 0
        return SteamApp(
            appID: appID,
            name: name,
            installDirectory: steamapps.appending(path: "common/\(installDirectory)", directoryHint: .isDirectory),
            sizeOnDisk: state["SizeOnDisk"]?.string.flatMap(Int64.init) ?? 0,
            // Bit 4 means "fully installed"; other bits mark updates in progress.
            isFullyInstalled: flags & 4 != 0
        )
    }
}
