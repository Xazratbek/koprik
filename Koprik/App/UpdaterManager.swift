import AppKit
import Combine
import Foundation
import Sparkle

/// Owns Sparkle's updater.
///
/// An `ObservableObject` rather than `@Observable`, because Sparkle reports
/// `canCheckForUpdates` through KVO and Combine bridges that directly.
@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    /// Sparkle refuses to run without a feed and a public key. A build made
    /// before the release setup (see docs/RELIZ.md) has neither, and must not
    /// start the updater: Sparkle would show an error dialog at every launch.
    let isConfigured: Bool = {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        return !key.isEmpty && !feed.isEmpty && !feed.contains("OWNER")
    }()

    var automaticallyChecksForUpdates: Bool {
        get { isConfigured && controller.updater.automaticallyChecksForUpdates }
        set { if isConfigured { controller.updater.automaticallyChecksForUpdates = newValue } }
    }

    private override init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
        guard isConfigured else { return }
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
    }

    /// Called once the app has launched. Debug builds never update themselves:
    /// Sparkle would replace the build being worked on with a release.
    func start() {
        #if !DEBUG
        guard isConfigured else { return }
        controller.startUpdater()
        #endif
    }

    func checkForUpdates() {
        #if !DEBUG
        guard isConfigured else { return }
        NSApp.activate()
        controller.checkForUpdates(nil)
        #endif
    }
}
