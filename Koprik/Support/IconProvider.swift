import AppKit
import KoprikKit
import SwiftUI

/// Loads and caches program icons and game artwork.
@MainActor
final class IconProvider {
    static let shared = IconProvider()

    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []
    private var artwork: [Int: NSImage] = [:]
    private var artworkMissing: Set<Int> = []

    func cachedIcon(for item: LibraryItem) -> NSImage? {
        icons[item.id]
    }

    /// The icon stored inside the program's executable.
    func icon(for item: LibraryItem) async -> NSImage? {
        if let cached = icons[item.id] { return cached }
        if missing.contains(item.id) { return nil }

        let executable = item.program.mainExecutable(in: item.bottle)
        guard let executable else {
            missing.insert(item.id)
            return nil
        }
        let data = await Task.detached(priority: .utility) { PEFile(url: executable)?.iconFileData }.value
        guard let data, let image = NSImage(data: data), image.isValid else {
            missing.insert(item.id)
            return nil
        }
        icons[item.id] = image
        return image
    }

    /// Steam's portrait cover for a game, kept on disk after the first download.
    func artwork(forSteamApp appID: Int) async -> NSImage? {
        if let cached = artwork[appID] { return cached }
        if artworkMissing.contains(appID) { return nil }

        let folder = AppPaths.default.cache.appending(path: "artwork", directoryHint: .isDirectory)
        let file = folder.appending(path: "\(appID).jpg")
        if let image = NSImage(contentsOf: file) {
            artwork[appID] = image
            return image
        }
        let sources = [
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg",
            "https://cdn.cloudflare.steamstatic.com/steam/apps/\(appID)/header.jpg",
        ]
        for source in sources {
            guard let url = URL(string: source),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = NSImage(data: data) else { continue }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            artwork[appID] = image
            return image
        }
        artworkMissing.insert(appID)
        return nil
    }
}

/// A program's icon at a fixed size, with a placeholder until it loads.
struct ProgramIcon: View {
    let item: LibraryItem
    var size: CGFloat = 64

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: item.program.kind == .steam ? "gamecontroller.fill" : "macwindow")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.18)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .task(id: item.id) {
            image = await IconProvider.shared.icon(for: item)
        }
    }
}
