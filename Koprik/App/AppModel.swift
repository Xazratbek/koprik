import AppKit
import KoprikKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// A program together with the bottle it lives in: what the library shows.
struct LibraryItem: Identifiable, Hashable {
    let bottle: Bottle
    var program: Program

    var id: String { "\(bottle.id.uuidString)/\(program.id)" }

    static func == (lhs: LibraryItem, rhs: LibraryItem) -> Bool {
        lhs.id == rhs.id && lhs.program == rhs.program && lhs.bottle == rhs.bottle
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, games, apps, favorites, recent

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .games: "Games"
        case .apps: "Apps"
        case .favorites: "Favorites"
        case .recent: "Recently Played"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .games: "gamecontroller"
        case .apps: "macwindow"
        case .favorites: "star"
        case .recent: "clock"
        }
    }
}

enum SidebarItem: Hashable {
    case library(LibraryFilter)
    case bottle(UUID)
    case install
    case activity
    case settings
    case store(StoreGame.Store)
    case controllers
}

/// Something long-running the user started: a download or an installation.
struct ActivityTask: Identifiable {
    enum State: Equatable {
        case running
        case finished
        case failed(String)
    }

    let id = UUID()
    var title: String
    var detail: String
    var fraction: Double?
    var state: State = .running
    let started = Date.now
}

struct AlertInfo: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

/// Sheets the main window can show.
enum AppSheet: Identifiable {
    case newBottle
    case runCommand(Bottle)
    case winetricks(Bottle)
    case snapshots(Bottle)
    case palette

    var id: String {
        switch self {
        case .newBottle: "newBottle"
        case .runCommand(let bottle): "run-\(bottle.id)"
        case .winetricks(let bottle): "winetricks-\(bottle.id)"
        case .snapshots(let bottle): "snapshots-\(bottle.id)"
        case .palette: "palette"
        }
    }
}

/// The log of a finished or running launch, shown in the log window.
struct LogReference: Identifiable, Hashable {
    var title: String
    var url: URL

    var id: URL { url }
}

/// The app's state and every action the interface can take.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: State

    var sheet: AppSheet?
    var settingsTab = SettingsTab.general

    /// Whether the page in view lists programs (the library and bottle pages do).
    var selectionShowsPrograms: Bool {
        switch sidebarSelection {
        case .library, .bottle, nil: true
        case .install, .activity, .settings, .store, .controllers: false
        }
    }

    // MARK: Whisky and saves

    var whiskyBottles: [WhiskyBottle] = []

    func findWhiskyBottles() {
        let known = Set(bottles.map(\.config.notes))
        whiskyBottles = WhiskyImport.bottles().filter { bottle in !known.contains { $0.contains(bottle.url.path) } }
    }

    func importWhisky(_ source: WhiskyBottle) {
        guard let engine = preferredEngine else { return }
        runTask(title: String(localized: "Importing from Whisky"), detail: source.name) { [bottleStore] _ in
            _ = try await bottleStore.importWhisky(source, engine: engine)
        } completion: { [weak self] in
            await self?.reload()
            self?.findWhiskyBottles()
        }
    }

    static var backupsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents/Koprik Backups", directoryHint: .isDirectory)
    }

    func backUpSaves(of bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        runTask(title: String(localized: "Backing up saves"), detail: bottle.name) { _ in
            let archive = try await BottleTools(bottle: bottle, engine: engine).backupSaves(to: Self.backupsFolder)
            await MainActor.run { NSWorkspace.shared.activateFileViewerSelecting([archive]) }
        } completion: {}
    }

    func restoreSaves(of bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        let panel = NSOpenPanel()
        panel.directoryURL = Self.backupsFolder
        panel.title = String(localized: "Choose a saves backup")
        guard panel.runModal() == .OK, let archive = panel.url else { return }
        runTask(title: String(localized: "Restoring saves"), detail: bottle.name) { _ in
            try await BottleTools(bottle: bottle, engine: engine).restoreSaves(from: archive)
        } completion: {}
    }

    // MARK: Stores

    struct StoreState {
        var loggedIn = false
        var loading = false
        var games: [StoreGame] = []
        var error: String?
    }

    var storeStates: [StoreGame.Store: StoreState] = [:]
    var installingStoreGames: Set<String> = []
    @ObservationIgnored let epicStore = EpicStore()
    @ObservationIgnored let gogStore = GOGStore()

    func refreshStore(_ store: StoreGame.Store) async {
        var state = storeStates[store] ?? StoreState()
        state.loggedIn = store == .epic ? await epicStore.isLoggedIn : await gogStore.isLoggedIn
        guard state.loggedIn else {
            storeStates[store] = state
            return
        }
        state.loading = true
        storeStates[store] = state
        do {
            state.games = store == .epic ? try await epicStore.library() : try await gogStore.library(installedIn: bottles)
            state.error = nil
        } catch {
            state.error = error.localizedDescription
        }
        state.loading = false
        storeStates[store] = state
    }

    func signIn(to store: StoreGame.Store, code: String) async {
        do {
            if store == .epic {
                try await epicStore.login(code: code)
            } else {
                try await gogStore.login(code: code)
            }
            await refreshStore(store)
        } catch {
            present(error)
        }
    }

    func signOut(of store: StoreGame.Store) async {
        if store == .epic { await epicStore.logout() } else { await gogStore.logout() }
        storeStates[store] = StoreState()
    }

    /// The library entry of an installed store game, if Ko'prik has found it.
    func libraryItem(for game: StoreGame) -> LibraryItem? {
        guard game.isInstalled else { return nil }
        return allItems.first { $0.program.storeID == game.storeID && $0.program.kind.rawValue == game.store.rawValue }
    }

    func installStoreGame(_ game: StoreGame, into bottleID: UUID?) {
        installingStoreGames.insert(game.id)
        Task {
            var bottle = bottleID.flatMap(bottle(id:))
            if bottle == nil, let engine = preferredEngine {
                let name = game.store == .epic ? "Epic Games" : "GOG"
                if let existing = bottles.first(where: { $0.name == name }) {
                    bottle = existing
                } else {
                    bottle = await createBottle(name: name, windowsVersion: .win10, engine: engine)
                }
            }
            guard let bottle else {
                installingStoreGames.remove(game.id)
                return
            }
            let taskID = addTask(title: String(localized: "Installing \(game.title)"), detail: bottle.name)
            do {
                if game.store == .epic {
                    try await epicStore.install(game, into: bottle)
                } else {
                    try await gogStore.install(game, into: bottle)
                }
                finishTask(taskID)
            } catch {
                failTask(taskID, error)
                present(error)
            }
            installingStoreGames.remove(game.id)
            await reloadPrograms(of: bottle)
            await refreshStore(game.store)
        }
    }

    /// Opens the settings page inside the main window.
    func showSettings(tab: SettingsTab? = nil) {
        if let tab { settingsTab = tab }
        sidebarSelection = .settings
    }
    var engines: [Engine] = []
    var bottles: [Bottle] = []
    var programsByBottle: [UUID: [Program]] = [:]
    var isLoaded = false
    var rosettaAvailable = true

    var sidebarSelection: SidebarItem? = .library(.all)
    var selectedItemID: String?
    var searchText = ""
    var showInspector = false

    var tasks: [ActivityTask] = []
    var alert: AlertInfo?
    var presentedLog: LogReference?

    /// Bottles with a live wineserver.
    var runningBottles: Set<UUID> = []
    var processes: [WindowsProcess] = []
    /// Library items that have a process running right now, with their start time.
    var runningSince: [String: Date] = [:]
    /// Items whose launch was requested and whose window has not appeared yet.
    var launching: Set<String> = []
    /// The backend each running or recently started item was given, and why.
    var lastDecision: [String: GraphicsDecision] = [:]
    var compatibility: [String: CompatibilityReport] = [:]

    // MARK: Services

    let engineStore = EngineStore()
    let bottleStore = BottleStore()
    let programStore = ProgramStore()
    let compatibilityService = CompatibilityService()
    @ObservationIgnored private var monitor: Task<Void, Never>?

    // MARK: Derived

    var allItems: [LibraryItem] {
        bottles.flatMap { bottle in
            (programsByBottle[bottle.id] ?? []).map { LibraryItem(bottle: bottle, program: $0) }
        }
    }

    func items(for filter: LibraryFilter) -> [LibraryItem] {
        let base: [LibraryItem] = switch filter {
        case .all: allItems
        case .games: allItems.filter { $0.program.kind == .steam }
        case .apps: allItems.filter { $0.program.kind == .executable }
        case .favorites: allItems.filter(\.program.favorite)
        case .recent:
            allItems.filter { $0.program.lastPlayed != nil }
                .sorted { ($0.program.lastPlayed ?? .distantPast) > ($1.program.lastPlayed ?? .distantPast) }
        }
        return search(base, sorted: filter != .recent)
    }

    func items(inBottle id: UUID) -> [LibraryItem] {
        search(allItems.filter { $0.bottle.id == id }, sorted: true)
    }

    private func search(_ items: [LibraryItem], sorted: Bool) -> [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty ? items : items.filter { $0.program.name.localizedCaseInsensitiveContains(query) }
        return sorted
            ? matching.sorted { $0.program.name.localizedStandardCompare($1.program.name) == .orderedAscending }
            : matching
    }

    var selectedItem: LibraryItem? {
        guard let selectedItemID else { return nil }
        return allItems.first { $0.id == selectedItemID }
    }

    func bottle(id: UUID) -> Bottle? {
        bottles.first { $0.id == id }
    }

    func engine(for bottle: Bottle) -> Engine? {
        engines.first { $0.id == bottle.config.engineID }
    }

    var preferredEngine: Engine? {
        engines.first(where: \.manifest.d3dmetalCapable) ?? engines.first
    }

    var needsOnboarding: Bool {
        isLoaded && (engines.isEmpty || !rosettaAvailable)
    }

    // MARK: Loading

    func start() {
        guard monitor == nil else { return }
        monitor = Task { [weak self] in
            await self?.reload()
            while !Task.isCancelled {
                await self?.refreshActivity()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func reload() async {
        rosettaAvailable = await Rosetta.isAvailable()
        engines = (try? await engineStore.installed()) ?? []
        bottles = (try? await bottleStore.all()) ?? []
        for bottle in bottles {
            programsByBottle[bottle.id] = await programStore.programs(in: bottle)
        }
        programsByBottle = programsByBottle.filter { id, _ in bottles.contains { $0.id == id } }
        isLoaded = true
    }

    func reloadPrograms(of bottle: Bottle) async {
        programsByBottle[bottle.id] = await programStore.programs(in: bottle)
    }

    /// Watches which bottles and programs are running, and books play time
    /// when a program stops. Works the same for programs started elsewhere,
    /// for example by Steam itself or from the command-line tool.
    func refreshActivity() async {
        let running = Set(bottles.filter { BottleActivity.isRunning($0) }.map(\.id))
        if running != runningBottles { runningBottles = running }
        guard !running.isEmpty || !runningSince.isEmpty else {
            if !processes.isEmpty { processes = [] }
            return
        }

        let current = await BottleActivity.windowsProcesses()
        if current != processes { processes = current }
        let paths = current.map { $0.path.lowercased() }

        var active: Set<String> = []
        for item in allItems where running.contains(item.bottle.id) {
            if let needle = Self.processNeedle(for: item), paths.contains(where: { $0.contains(needle) }) {
                active.insert(item.id)
            }
        }
        for id in active where runningSince[id] == nil {
            runningSince[id] = .now
            launching.remove(id)
        }
        for (id, started) in runningSince where !active.contains(id) {
            runningSince[id] = nil
            if let item = allItems.first(where: { $0.id == id }) {
                _ = try? await programStore.recordSession(
                    programID: item.program.id, in: item.bottle, started: started, duration: Date.now.timeIntervalSince(started)
                )
                await reloadPrograms(of: item.bottle)
            }
        }
        // New games appear while Steam is open; pick them up without a manual refresh.
        for bottle in bottles where running.contains(bottle.id) {
            let fresh = await programStore.programs(in: bottle)
            if fresh != programsByBottle[bottle.id] { programsByBottle[bottle.id] = fresh }
        }
    }

    /// A lowercased fragment that a process path must contain to belong to the item.
    private static func processNeedle(for item: LibraryItem) -> String? {
        switch item.program.kind {
        case .steam:
            let folder = URL(fileURLWithPath: item.program.location).lastPathComponent
            return "\\steamapps\\common\\\(folder)\\".lowercased()
        case .epic, .gog:
            let folder = URL(fileURLWithPath: item.program.location).lastPathComponent
            return "\\\(folder)\\".lowercased()
        case .executable:
            if item.program.location.hasPrefix("/") {
                return URL(fileURLWithPath: item.program.location).lastPathComponent.lowercased()
            }
            return item.program.location.lowercased()
        }
    }

    // MARK: Engines

    func installEngine(_ source: EngineSource) {
        runTask(title: String(localized: "Installing engine"), detail: source.displayName) { [engineStore] update in
            _ = try await engineStore.install(source) { progress in
                Task { @MainActor in update(progress.fraction, nil) }
            }
        } completion: { [weak self] in
            await self?.reload()
        }
    }

    func removeEngine(_ engine: Engine) async {
        let users = bottles.filter { $0.config.engineID == engine.id }
        guard users.isEmpty else {
            present(String(localized: "Engine in use"),
                    String(localized: "These bottles still use it: \(users.map(\.name).joined(separator: ", "))"))
            return
        }
        do {
            try await engineStore.remove(id: engine.id)
            await reload()
        } catch {
            present(error)
        }
    }

    func importGPTK(from url: URL, into engine: Engine) {
        runTask(title: String(localized: "Importing Game Porting Toolkit"), detail: url.lastPathComponent) { _ in
            _ = try await GPTKImporter.importToolkit(from: url, into: engine)
        } completion: { [weak self] in
            await self?.reload()
        }
    }

    // MARK: Bottles

    @discardableResult
    func createBottle(name: String, windowsVersion: WindowsVersion, engine: Engine) async -> Bottle? {
        let taskID = addTask(title: String(localized: "Creating bottle"), detail: name)
        do {
            let bottle = try await bottleStore.create(name: name, engine: engine, windowsVersion: windowsVersion)
            finishTask(taskID)
            await reload()
            return bottle
        } catch {
            failTask(taskID, error)
            present(error)
            return nil
        }
    }

    func rename(_ bottle: Bottle, to name: String) async {
        await perform { _ = try await self.bottleStore.rename(bottle, to: name) }
    }

    func duplicate(_ bottle: Bottle) async {
        await stopAll(in: bottle)
        var name = "\(bottle.name) copy"
        var counter = 2
        while bottles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(bottle.name) copy \(counter)"
            counter += 1
        }
        await perform { _ = try await self.bottleStore.duplicate(bottle, as: name) }
    }

    func delete(_ bottle: Bottle) async {
        await stopAll(in: bottle)
        if sidebarSelection == .bottle(bottle.id) { sidebarSelection = .library(.all) }
        await perform { try await self.bottleStore.delete(bottle) }
    }

    func update(_ bottle: Bottle) async {
        await perform { _ = try await self.bottleStore.save(bottle) }
    }

    func stopAll(in bottle: Bottle) async {
        guard let engine = engine(for: bottle) else { return }
        await Launcher(bottle: bottle, engine: engine).stopAll()
        await refreshActivity()
    }

    func stopEverything() async {
        for bottle in bottles where runningBottles.contains(bottle.id) {
            await stopAll(in: bottle)
        }
    }

    func snapshot(_ bottle: Bottle, label: String) async {
        await stopAll(in: bottle)
        let taskID = addTask(title: String(localized: "Saving snapshot"), detail: bottle.name)
        do {
            _ = try await bottleStore.snapshot(bottle, label: label)
            finishTask(taskID)
        } catch {
            failTask(taskID, error)
            present(error)
        }
    }

    func restore(_ bottle: Bottle, snapshot: BottleSnapshot) async {
        await stopAll(in: bottle)
        await perform { try await self.bottleStore.restore(bottle, snapshotID: snapshot.id) }
    }

    // MARK: Programs

    func save(_ program: Program, in bottle: Bottle) async {
        do {
            _ = try await programStore.save(program, in: bottle)
            await reloadPrograms(of: bottle)
        } catch {
            present(error)
        }
    }

    func toggleFavorite(_ item: LibraryItem) async {
        var program = item.program
        program.favorite.toggle()
        await save(program, in: item.bottle)
    }

    func hide(_ item: LibraryItem) async {
        var program = item.program
        program.hidden = true
        if selectedItemID == item.id { selectedItemID = nil }
        await save(program, in: item.bottle)
    }

    /// Closes one program, leaving the rest of its bottle (Steam, say) running.
    func stop(_ item: LibraryItem) async {
        guard let engine = engine(for: item.bottle) else { return }
        guard let name = item.program.mainExecutable(in: item.bottle)?.lastPathComponent else {
            await stopAll(in: item.bottle)
            return
        }
        await Launcher(bottle: item.bottle, engine: engine).stop(programNamed: name)
        await refreshActivity()
    }

    func isRunning(_ item: LibraryItem) -> Bool {
        runningSince[item.id] != nil
    }

    func launch(_ item: LibraryItem, overrides: LaunchSettings = LaunchSettings()) {
        guard let engine = engine(for: item.bottle) else {
            present(String(localized: "Engine missing"),
                    String(localized: "This bottle uses the engine \(item.bottle.config.engineID), which is not installed."))
            return
        }
        launching.insert(item.id)
        Task {
            do {
                let launch = try await Launcher(bottle: item.bottle, engine: engine)
                    .launch(.program(item.program), overrides: overrides)
                lastDecision[item.id] = launch.graphics
                watch(launch, title: item.program.name, itemID: item.id)
            } catch {
                launching.remove(item.id)
                present(error)
            }
        }
    }

    /// Runs a file from the Mac (an installer or a portable program) in a bottle.
    func run(file: URL, arguments: [String] = [], in bottle: Bottle, overrides: LaunchSettings = LaunchSettings()) {
        guard let engine = engine(for: bottle) else { return }
        Task {
            do {
                let launch = try await Launcher(bottle: bottle, engine: engine)
                    .launch(.file(file, arguments: arguments), overrides: overrides)
                watch(launch, title: file.lastPathComponent, itemID: nil, bottle: bottle)
            } catch {
                present(error)
            }
        }
    }

    /// Runs a Windows command such as `winecfg`, `regedit` or `taskmgr`.
    func run(command: String, arguments: [String] = [], in bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        Task {
            do {
                let launch = try await Launcher(bottle: bottle, engine: engine)
                    .launch(.command(command, arguments: arguments))
                watch(launch, title: command, itemID: nil, bottle: bottle)
            } catch {
                present(error)
            }
        }
    }

    /// Follows a launch to its end. A program that dies within seconds almost
    /// always failed, so its log is analysed and shown without being asked for.
    private func watch(_ launch: Launch, title: String, itemID: String?, bottle: Bottle? = nil) {
        let started = Date.now
        Task {
            let status = await launch.process.waitUntilExit()
            if let itemID { launching.remove(itemID) }
            if let bottle { await reloadPrograms(of: bottle) }
            let quick = Date.now.timeIntervalSince(started) < 20
            if status != 0, quick {
                let summary = LogAnalyzer.analyze(fileAt: launch.process.logURL)
                if summary.findings.contains(where: { $0.severity == .error }) || status != 0 {
                    presentedLog = LogReference(title: title, url: launch.process.logURL)
                }
            }
        }
    }

    func install(_ recipe: Recipe, into bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        let hasContent = !(programsByBottle[bottle.id] ?? []).isEmpty
        runTask(title: String(localized: "Installing \(recipe.name)"), detail: bottle.name) { update in
            try await Installer(bottle: bottle, engine: engine).install(recipe, snapshotFirst: hasContent) { stage in
                Task { @MainActor in
                    switch stage {
                    case .snapshotting: update(nil, String(localized: "Saving a snapshot first"))
                    case .downloading(let fraction): update(fraction, String(localized: "Downloading"))
                    case .verifying: update(nil, String(localized: "Verifying the download"))
                    case .runningWinetricks(let verbs): update(nil, String(localized: "Installing \(verbs)"))
                    case .runningInstaller: update(nil, String(localized: "Running the installer"))
                    case .finished: update(1, nil)
                    }
                }
            }
        } completion: { [weak self] in
            await self?.reloadPrograms(of: bottle)
        }
    }

    func runWinetricks(_ verbs: [String], in bottle: Bottle) {
        guard let engine = engine(for: bottle) else { return }
        runTask(title: String(localized: "Installing \(verbs.joined(separator: ", "))"), detail: bottle.name) { _ in
            try await Winetricks().run(verbs: verbs, bottle: bottle, engine: engine)
        } completion: {}
    }

    func pin(executable: URL, in bottle: Bottle) async {
        do {
            let program = try await programStore.pin(executable: executable, in: bottle)
            await reloadPrograms(of: bottle)
            selectedItemID = LibraryItem(bottle: bottle, program: program).id
        } catch {
            present(error)
        }
    }

    func createLauncher(for item: LibraryItem) {
        do {
            let bundle = try AppLauncherBuilder.create(for: item.program, in: item.bottle)
            if let icon = IconProvider.shared.cachedIcon(for: item) {
                NSWorkspace.shared.setIcon(icon, forFile: bundle.path)
            }
            NSWorkspace.shared.activateFileViewerSelecting([bundle])
        } catch {
            present(error)
        }
    }

    func loadCompatibility(for item: LibraryItem) async {
        guard compatibility[item.id] == nil else { return }
        let report = if let appID = item.program.steamAppID {
            await compatibilityService.report(forSteamApp: appID, name: item.program.name)
        } else {
            await compatibilityService.report(forName: item.program.name)
        }
        compatibility[item.id] = report
    }

    func graphicsDecision(for item: LibraryItem) -> GraphicsDecision? {
        guard let engine = engine(for: item.bottle) else { return nil }
        return Launcher(bottle: item.bottle, engine: engine).graphicsDecision(for: .program(item.program))
    }

    // MARK: Opening things from outside

    /// Handles a file dropped on the app or opened from Finder.
    func open(file: URL) {
        let type = file.pathExtension.lowercased()
        guard ["exe", "msi", "bat", "lnk"].contains(type) else { return }
        if let bottle = currentBottle ?? bottles.first {
            run(file: file, in: bottle)
        } else {
            present(String(localized: "No bottle yet"), String(localized: "Create a bottle first, then open the file again."))
        }
    }

    func open(url: URL) {
        if url.isFileURL {
            open(file: url)
        } else if url.scheme?.lowercased() == "koprik", url.host()?.lowercased() == "show" {
            show(section: url.pathComponents.filter { $0 != "/" })
        } else if let target = AppLauncherBuilder.parse(url),
                  let item = allItems.first(where: { $0.bottle.id == target.bottleID && $0.program.id == target.programID }) {
            launch(item)
        }
    }

    /// Handles `koprik://show/...` links, which jump to a part of the app:
    /// `install`, `activity`, `library/<filter>`, `bottle/<name or id>`,
    /// `program/<name>` and `settings/<tab>`. Handy from Shortcuts and scripts.
    private func show(section parts: [String]) {
        guard let first = parts.first?.lowercased() else { return }
        let argument = parts.dropFirst().first?.removingPercentEncoding
        switch first {
        case "install": sidebarSelection = .install
        case "activity": sidebarSelection = .activity
        case "library":
            sidebarSelection = .library(argument.flatMap { LibraryFilter(rawValue: $0.lowercased()) } ?? .all)
        case "bottle":
            if let argument, let bottle = bottles.first(where: {
                $0.name.caseInsensitiveCompare(argument) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(argument) == .orderedSame
            }) {
                sidebarSelection = .bottle(bottle.id)
            }
        case "program":
            if let argument, let item = allItems.first(where: { $0.program.name.caseInsensitiveCompare(argument) == .orderedSame }) {
                selectedItemID = item.id
                showInspector = true
            }
        case "settings":
            showSettings(tab: argument.flatMap { SettingsTab(rawValue: $0.lowercased()) })
        default:
            break
        }
    }

    /// Asks for a Windows file and runs it in the bottle in view.
    func chooseFileToRun(in bottle: Bottle? = nil) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a Windows program or installer")
        panel.allowedContentTypes = ["exe", "msi", "bat", "lnk"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let file = panel.url else { return }
        if let bottle {
            run(file: file, in: bottle)
        } else {
            open(file: file)
        }
    }

    /// The bottle the user is looking at, if the selection implies one.
    var currentBottle: Bottle? {
        if case .bottle(let id) = sidebarSelection { return bottle(id: id) }
        return selectedItem?.bottle
    }

    // MARK: Tasks and errors

    private func addTask(title: String, detail: String) -> UUID {
        let task = ActivityTask(title: title, detail: detail)
        tasks.insert(task, at: 0)
        return task.id
    }

    private func updateTask(_ id: UUID, fraction: Double?, detail: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].fraction = fraction
        if let detail { tasks[index].detail = detail }
    }

    private func finishTask(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .finished
        tasks[index].fraction = 1
    }

    private func failTask(_ id: UUID, _ error: Error) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = .failed(error.localizedDescription)
    }

    var activeTaskCount: Int {
        tasks.count { $0.state == .running }
    }

    func clearFinishedTasks() {
        tasks.removeAll { $0.state != .running }
    }

    /// Runs `work` as a visible task. `update` reports a fraction and, optionally, a new detail line.
    private func runTask(
        title: String,
        detail: String,
        work: @escaping @Sendable (_ update: @escaping @MainActor (Double?, String?) -> Void) async throws -> Void,
        completion: @escaping @MainActor () async -> Void
    ) {
        let id = addTask(title: title, detail: detail)
        Task {
            do {
                try await work { [weak self] fraction, detail in
                    self?.updateTask(id, fraction: fraction, detail: detail)
                }
                finishTask(id)
            } catch {
                failTask(id, error)
                present(error)
            }
            await completion()
        }
    }

    private func perform(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            present(error)
        }
        await reload()
    }

    func present(_ error: Error) {
        alert = AlertInfo(title: String(localized: "Something went wrong"), message: error.localizedDescription)
    }

    func present(_ title: String, _ message: String) {
        alert = AlertInfo(title: title, message: message)
    }
}
