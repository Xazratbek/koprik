import AppIntents
import KoprikKit

/// A program in the library, as Shortcuts and Siri see it.
struct ProgramEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Windows Program"
    static let defaultQuery = ProgramQuery()

    let id: String
    let name: String
    let bottleName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(bottleName)")
    }
}

struct ProgramQuery: EntityStringQuery {
    @MainActor
    private func all() async -> [ProgramEntity] {
        let model = AppModel.shared
        if !model.isLoaded { await model.reload() }
        return model.allItems.map { ProgramEntity(id: $0.id, name: $0.program.name, bottleName: $0.bottle.name) }
    }

    func entities(for identifiers: [String]) async throws -> [ProgramEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [ProgramEntity] {
        await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [ProgramEntity] {
        await all()
    }
}

struct PlayProgramIntent: AppIntent {
    static let title: LocalizedStringResource = "Play a Windows Program"
    static let description = IntentDescription("Starts a game or program from your Ko'prik library.")
    static let openAppWhenRun = false

    @Parameter(title: "Program") var program: ProgramEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if !model.isLoaded { await model.reload() }
        guard let item = model.allItems.first(where: { $0.id == program.id }) else {
            throw $program.needsValueError()
        }
        model.launch(item)
        return .result()
    }
}

struct StopEverythingIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop All Windows Programs"
    static let description = IntentDescription("Closes every Windows program Ko'prik is running.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        let model = AppModel.shared
        if !model.isLoaded { await model.reload() }
        await model.stopEverything()
        return .result()
    }
}

struct KoprikShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PlayProgramIntent(),
            phrases: ["Play \(\.$program) in \(.applicationName)", "Start \(\.$program) with \(.applicationName)"],
            shortTitle: "Play",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopEverythingIntent(),
            phrases: ["Stop everything in \(.applicationName)"],
            shortTitle: "Stop Everything",
            systemImageName: "stop.circle"
        )
    }
}
