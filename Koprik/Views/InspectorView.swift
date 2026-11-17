import KoprikKit
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let item = model.selectedItem {
            ProgramInspector(item: item)
                .id(item.id)
        } else {
            ContentUnavailableView("No Selection", systemImage: "cursorarrow.click.2", description: Text("Select a program to see and change how it runs."))
        }
    }
}

/// Everything about one program: its state, compatibility and settings.
struct ProgramInspector: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    @State private var program: Program
    @State private var argumentsText: String

    init(item: LibraryItem) {
        self.item = item
        _program = State(initialValue: item.program)
        _argumentsText = State(initialValue: item.program.arguments.joined(separator: " "))
    }

    var body: some View {
        Form {
            Section {
                header
            }

            if let report = model.compatibility[item.id], report.antiCheat != nil || report.protonTier != nil {
                Section("Compatibility") {
                    CompatibilityRows(report: report)
                }
            }

            Section("Graphics") {
                LaunchSettingsRows(settings: $program.settings, inherited: inherited)
                if let decision = model.graphicsDecision(for: LibraryItem(bottle: item.bottle, program: program)) {
                    LabeledContent("Will use") {
                        Text(verbatim: decision.backend.displayName).fontWeight(.medium)
                    }
                    Text(verbatim: decision.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Launch") {
                TextField("Arguments", text: $argumentsText, prompt: Text(verbatim: "-windowed -novid"))
                    .onSubmit(commit)
                KeyValueEditor(title: "Environment", pairs: Binding(
                    get: { program.settings.environment ?? [:] },
                    set: { program.settings.environment = $0.isEmpty ? nil : $0 }
                ), keyPrompt: "NAME", valuePrompt: "value")
                KeyValueEditor(title: "DLL Overrides", pairs: Binding(
                    get: { program.settings.dllOverrides ?? [:] },
                    set: { program.settings.dllOverrides = $0.isEmpty ? nil : $0 }
                ), keyPrompt: "d3dcompiler_47", valuePrompt: "n,b")
            }

            Section("Statistics") {
                LabeledContent("Play time") { Text(Self.duration(program.playTime)) }
                LabeledContent("Launches") { Text(program.launchCount, format: .number) }
                if let last = program.lastPlayed {
                    LabeledContent("Last played") { Text(last, format: .relative(presentation: .named)) }
                }
                LabeledContent("Bottle") { Text(verbatim: item.bottle.name) }
            }

            Section {
                Button("Create App Launcher", systemImage: "app.badge") { model.createLauncher(for: item) }
                Button("Show Latest Log", systemImage: "doc.text.magnifyingglass") { showLatestLog() }
                Button("Reset Settings", systemImage: "arrow.counterclockwise") {
                    program.settings = LaunchSettings()
                    argumentsText = ""
                    commit()
                }
                .disabled(program.settings == LaunchSettings() && argumentsText.isEmpty)
            }
        }
        .formStyle(.grouped)
        .onChange(of: program.settings) { commit() }
        .task { await model.loadCompatibility(for: item) }
    }

    private var inherited: LaunchSettings {
        LaunchSettings.resolve([model.engine(for: item.bottle)?.defaultSettings ?? LaunchSettings(), item.bottle.config.settings])
    }

    private var header: some View {
        HStack(spacing: 14) {
            ProgramIcon(item: item, size: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: program.name)
                    .font(.headline)
                    .lineLimit(2)
                HStack {
                    if model.isRunning(item) {
                        Button("Stop", systemImage: "stop.fill") { Task { await model.stop(item) } }
                            .tint(.red)
                    } else {
                        Button("Play", systemImage: "play.fill") { model.launch(item) }
                            .buttonStyle(.borderedProminent)
                    }
                    Button {
                        Task { await model.toggleFavorite(item) }
                        program.favorite.toggle()
                    } label: {
                        Image(systemName: program.favorite ? "star.fill" : "star")
                    }
                    .help("Favorite")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        var updated = program
        updated.arguments = ProgramArguments.split(argumentsText)
        // Statistics are owned by the model's activity monitor; keep whatever it last stored.
        if let current = model.selectedItem?.program, current.id == updated.id {
            updated.launchCount = current.launchCount
            updated.playTime = current.playTime
            updated.lastPlayed = current.lastPlayed
            updated.favorite = current.favorite
        }
        Task { await model.save(updated, in: item.bottle) }
    }

    private func showLatestLog() {
        let logs = (try? FileManager.default.contentsOfDirectory(at: item.bottle.logs, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let wanted = item.program.name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "_" }
        let matching = logs.filter { $0.lastPathComponent.contains(String(wanted)) }
        let newest = (matching.isEmpty ? logs : matching).max {
            let first = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let second = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return first < second
        }
        if let newest {
            model.presentedLog = LogReference(title: item.program.name, url: newest)
        } else {
            model.present(String(localized: "No log yet"), String(localized: "Run the program once and its log will be here."))
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(localized: "Less than a minute") }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

enum ProgramArguments {
    /// Splits a command line on spaces, keeping quoted parts together.
    static func split(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
            } else if character == " " && !quoted {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// The graphics and performance switches, used for programs and for bottles.
///
/// Every control has an "inherit" state, so a program only stores what it
/// overrides. `inherited` is what applies when the control is left alone.
struct LaunchSettingsRows: View {
    @Binding var settings: LaunchSettings
    var inherited: LaunchSettings?

    var body: some View {
        Picker("Backend", selection: $settings.backend) {
            Text(inheritLabel(inherited?.backend?.displayName ?? "Auto")).tag(GraphicsBackend?.none)
            Divider()
            ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                Text(verbatim: backend.displayName).tag(GraphicsBackend?.some(backend))
            }
        }
        .help("Auto picks by the Direct3D version the program uses.")

        Picker("Synchronisation", selection: $settings.sync) {
            Text(inheritLabel(inherited?.sync?.rawValue.uppercased() ?? "None")).tag(SyncMode?.none)
            Divider()
            Text(verbatim: "MSync").tag(SyncMode?.some(.msync))
            Text(verbatim: "ESync").tag(SyncMode?.some(.esync))
            Text("None").tag(SyncMode?.some(.none))
        }
        .help("MSync is fastest. Switch to ESync or None if a game hangs.")

        Picker("Frame rate limit", selection: $settings.maxFrameRate) {
            Text(inheritLabel(inherited?.maxFrameRate.map { $0 == 0 ? String(localized: "None") : "\($0)" } ?? String(localized: "None"))).tag(Int?.none)
            Divider()
            Text("None").tag(Int?.some(0))
            ForEach([30, 60, 90, 120, 144], id: \.self) { rate in
                Text(verbatim: "\(rate) FPS").tag(Int?.some(rate))
            }
        }
        .help("Caps the frame rate in DXMT and DXVK. A cap at the display's refresh rate gives the smoothest motion.")

        Picker("MetalFX upscaling", selection: $settings.metalFXUpscale) {
            Text(inheritLabel(inherited?.metalFXUpscale.map { $0 > 1 ? "\($0)×" : String(localized: "Off") } ?? String(localized: "Off"))).tag(Double?.none)
            Divider()
            Text("Off").tag(Double?.some(1))
            Text(verbatim: "1.5× (quality)").tag(Double?.some(1.5))
            Text(verbatim: "2× (performance)").tag(Double?.some(2))
        }
        .help("DXMT only. Renders at a lower resolution and lets Apple's MetalFX upscale it. More frames in demanding games.")

        Picker("Language", selection: $settings.language) {
            Text(inheritLabel(inherited?.language.flatMap { Self.languages[$0] } ?? String(localized: "Mac's language"))).tag(String?.none)
            Divider()
            ForEach(Self.languages.sorted { $0.value < $1.value }, id: \.key) { code, name in
                Text(verbatim: name).tag(String?.some(code))
            }
        }
        .help("The language and character set the program sees. Change it if text shows as garbage such as \"Ïðîâåðêà\".")

        OptionalToggle("Metal performance HUD", value: $settings.metalHUD)
        Picker("DXVK HUD", selection: $settings.dxvkHUD) {
            Text(inheritLabel(inherited?.dxvkHUD?.rawValue.capitalized ?? "Off")).tag(DXVKHud?.none)
            Divider()
            Text("Off").tag(DXVKHud?.some(.off))
            Text("Frame rate").tag(DXVKHud?.some(.fps))
            Text("Partial").tag(DXVKHud?.some(.partial))
            Text("Full").tag(DXVKHud?.some(.full))
        }
        OptionalToggle("DXVK async shaders", value: $settings.dxvkAsync, help: "Less stutter while shaders compile, at the cost of objects popping in.")
        OptionalToggle("Advertise AVX", value: $settings.advertiseAVX, help: "For games that refuse to start without AVX. Rosetta translates AVX and AVX2.")
        OptionalToggle("Ray tracing (D3DMetal)", value: $settings.raytracing, help: "DirectX Raytracing. Needs the Game Porting Toolkit and an M3 or newer for good results.")
    }

    private func inheritLabel(_ value: String) -> String {
        inherited == nil ? String(localized: "Default (\(value))") : String(localized: "Inherit (\(value))")
    }

    /// Locales offered for programs, by the name of the language in that language.
    static let languages: [String: String] = [
        "en_US": "English",
        "ru_RU": "Русский",
        "uz_UZ": "Oʻzbekcha",
        "tr_TR": "Türkçe",
        "de_DE": "Deutsch",
        "fr_FR": "Français",
        "es_ES": "Español",
        "pl_PL": "Polski",
        "uk_UA": "Українська",
        "ja_JP": "日本語",
        "zh_CN": "简体中文",
        "zh_TW": "繁體中文",
        "ko_KR": "한국어",
    ]
}

/// A switch over an optional setting: off means "not set here", so the layer below decides.
struct OptionalToggle: View {
    let title: LocalizedStringKey
    @Binding var value: Bool?
    var help: LocalizedStringKey?

    init(_ title: LocalizedStringKey, value: Binding<Bool?>, help: LocalizedStringKey? = nil) {
        self.title = title
        _value = value
        self.help = help
    }

    var body: some View {
        Toggle(isOn: Binding(get: { value ?? false }, set: { value = $0 ? true : nil })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let help {
                    Text(help).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// An editable list of name/value pairs.
struct KeyValueEditor: View {
    let title: LocalizedStringKey
    @Binding var pairs: [String: String]
    var keyPrompt: String
    var valuePrompt: String

    @State private var newKey = ""
    @State private var newValue = ""

    var body: some View {
        DisclosureGroup {
            ForEach(pairs.keys.sorted(), id: \.self) { key in
                HStack {
                    Text(verbatim: key).font(.callout.monospaced())
                    Spacer()
                    Text(verbatim: pairs[key] ?? "").font(.callout.monospaced()).foregroundStyle(.secondary)
                    Button {
                        pairs[key] = nil
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                TextField(text: $newKey, prompt: Text(verbatim: keyPrompt)) { EmptyView() }
                    .font(.callout.monospaced())
                TextField(text: $newValue, prompt: Text(verbatim: valuePrompt)) { EmptyView() }
                    .font(.callout.monospaced())
                    .onSubmit(add)
                Button(action: add) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .labelsHidden()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if !pairs.isEmpty {
                    Text(pairs.count, format: .number).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        pairs[key] = newValue.trimmingCharacters(in: .whitespaces)
        newKey = ""
        newValue = ""
    }
}

struct CompatibilityRows: View {
    let report: CompatibilityReport

    var body: some View {
        if let antiCheat = report.antiCheat {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(antiCheat.blocksPlay ? "Blocked by anti-cheat" : "Anti-cheat allows Wine")
                    Text(verbatim: report.antiCheatNames.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if antiCheat.blocksPlay {
                        Text("This game cannot be played online under Wine. No setting changes that.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: antiCheat.blocksPlay ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(antiCheat.blocksPlay ? .red : .green)
            }
        }
        if let tier = report.protonTier {
            LabeledContent("ProtonDB") {
                HStack(spacing: 6) {
                    Text(verbatim: tier.capitalized).fontWeight(.medium)
                    if let reports = report.protonReports {
                        Text("\(reports) reports").foregroundStyle(.secondary)
                    }
                }
            }
            Text("Ratings come from Linux players. Expect similar, not identical, results on a Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
