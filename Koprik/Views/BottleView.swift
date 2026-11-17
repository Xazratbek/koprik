import KoprikKit
import SwiftUI

/// One bottle: its programs, its tools and its settings.
struct BottleView: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    @State private var showSettings = false
    @State private var diskUsage: Int64?
    @State private var renaming = false
    @State private var newName = ""

    private var isRunning: Bool { model.runningBottles.contains(bottle.id) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            LibraryGrid(
                items: model.items(inBottle: bottle.id),
                emptyTitle: "This bottle is empty",
                emptyMessage: "Run an installer here, or drop a Windows .exe on the window."
            )
        }
        .navigationTitle(Text(verbatim: bottle.name))
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    BottleMenu(bottle: bottle)
                } label: {
                    Label("Bottle Actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            BottleSettingsSheet(bottle: bottle)
        }
        .alert("Rename Bottle", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Rename") { Task { await model.rename(bottle, to: newName) } }
            Button("Cancel", role: .cancel) {}
        }
        .task(id: bottle.id) {
            if let engine = model.engine(for: bottle) {
                diskUsage = await BottleTools(bottle: bottle, engine: engine).diskUsage()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: isRunning ? "cylinder.split.1x2.fill" : "cylinder.split.1x2")
                    .font(.system(size: 30))
                    .foregroundStyle(isRunning ? Color.green : Color.accentColor)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: bottle.name).font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(verbatim: bottle.config.windowsVersion.displayName)
                        Text(verbatim: "·")
                        Text(verbatim: model.engine(for: bottle)?.name ?? bottle.config.engineID)
                        if let diskUsage {
                            Text(verbatim: "·")
                            Text(diskUsage, format: .byteCount(style: .file))
                        }
                        if isRunning {
                            Text(verbatim: "·")
                            Text("Running").foregroundStyle(.green)
                        }
                        if (bottle.config.isolation ?? .off).isOn {
                            Text(verbatim: "·")
                            Label("Isolated", systemImage: "lock.shield.fill").foregroundStyle(.blue)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer()
                Button("Settings", systemImage: "slider.horizontal.3") { showSettings = true }
                Button("Rename", systemImage: "pencil") {
                    newName = bottle.name
                    renaming = true
                }
                .labelStyle(.iconOnly)
                .help("Rename")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ToolButton("Run File", systemImage: "doc.badge.gearshape") { model.chooseFileToRun(in: bottle) }
                    ToolButton("Run Command", systemImage: "terminal") { model.sheet = .runCommand(bottle) }
                    ToolButton("Components", systemImage: "shippingbox") { model.sheet = .winetricks(bottle) }
                    ToolButton("Wine Config", systemImage: "gearshape.2") { model.run(command: "winecfg", in: bottle) }
                    ToolButton("Registry", systemImage: "list.bullet.indent") { model.run(command: "regedit", in: bottle) }
                    ToolButton("Task Manager", systemImage: "chart.bar") { model.run(command: "taskmgr", in: bottle) }
                    ToolButton("Control Panel", systemImage: "switch.2") { model.run(command: "control", in: bottle) }
                    ToolButton("Uninstaller", systemImage: "trash.square") { model.run(command: "uninstaller", in: bottle) }
                    ToolButton("C: Drive", systemImage: "externaldrive") { NSWorkspace.shared.open(bottle.driveC) }
                    ToolButton("Snapshots", systemImage: "clock.arrow.circlepath") { model.sheet = .snapshots(bottle) }
                    ToolButton("Logs", systemImage: "doc.text") { NSWorkspace.shared.open(bottle.logs) }
                    if isRunning {
                        ToolButton("Stop All", systemImage: "stop.circle", tint: .red) { Task { await model.stopAll(in: bottle) } }
                    }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }
}

struct ToolButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color?
    let action: () -> Void

    init(_ title: LocalizedStringKey, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.glass)
        .tint(tint)
    }
}

/// Settings that apply to every program in a bottle unless the program overrides them.
struct BottleSettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var config: BottleConfig
    @State private var retina = false
    @State private var commandIsControl = false
    @State private var busy = false

    init(bottle: Bottle) {
        self.bottle = bottle
        _config = State(initialValue: bottle.config)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("General") {
                    Picker("Windows version", selection: $config.windowsVersion) {
                        ForEach(WindowsVersion.allCases, id: \.self) { version in
                            Text(verbatim: version.displayName).tag(version)
                        }
                    }
                    Picker("Engine", selection: $config.engineID) {
                        ForEach(model.engines) { engine in
                            Text(verbatim: engine.name).tag(engine.id)
                        }
                    }
                    TextField("Notes", text: $config.notes, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Picker("Isolation", selection: Binding(get: { config.isolation ?? .off }, set: { config.isolation = $0 })) {
                        Text("Off: full access, for trusted software").tag(Isolation.off)
                        Text("On: no access to your files or Mac programs").tag(Isolation.files)
                        Text("Strict: also no internet").tag(Isolation.full)
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Wine is not a sandbox: without isolation a Windows program can read and change your files. Isolated bottles run inside macOS's own sandbox, which a Windows program cannot switch off. Files you open from outside are copied in. Takes effect the next time the bottle starts.")
                }

                Section("Graphics and performance") {
                    LaunchSettingsRows(settings: $config.settings, inherited: nil)
                }

                Section("Display and keyboard") {
                    Toggle(isOn: Binding(
                        get: { config.exclusiveFullscreen ?? true },
                        set: { config.exclusiveFullscreen = $0 }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exclusive full screen")
                            Text("Full-screen games get the display to themselves: less input lag and a higher frame rate. Turn off for programs you switch away from often.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $retina) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("High resolution (Retina) mode")
                            Text("Sharper picture, heavier on the GPU. Applied when you press Save.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $commandIsControl) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Command acts as Ctrl")
                            Text("So that ⌘C and ⌘V work inside Windows programs.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Isolation") {
                    Button("Restrict File Access…", systemImage: "lock.shield") { restrict() }
                    Text("Removes the bottle's access to your home folder and other drives. Programs then only see the bottle's own C: drive.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(busy)
            }
            .padding()
        }
        .frame(width: 520, height: 640)
    }

    private func save() {
        busy = true
        Task {
            var updated = bottle
            updated.config = config
            await model.update(updated)
            if let engine = model.engines.first(where: { $0.id == config.engineID }) {
                let tools = BottleTools(bottle: updated, engine: engine)
                do {
                    if config.windowsVersion != bottle.config.windowsVersion {
                        try await tools.setWindowsVersion(config.windowsVersion)
                    }
                    if retina { try await tools.setRetinaMode(true) }
                    if commandIsControl { try await tools.setMacKeyboardMapping(commandIsControl: true, optionIsAlt: true) }
                } catch {
                    model.present(error)
                }
            }
            busy = false
            dismiss()
        }
    }

    private func restrict() {
        guard let engine = model.engine(for: bottle) else { return }
        do {
            try BottleTools(bottle: bottle, engine: engine).restrictFileAccess()
            model.present(String(localized: "File access restricted"),
                          String(localized: "This bottle can no longer reach files outside its own C: drive."))
        } catch {
            model.present(error)
        }
    }
}

/// The catalogue of software Ko'prik can install unattended.
struct InstallView: View {
    @Environment(AppModel.self) private var model
    @State private var targetBottleID: UUID?
    @State private var createNew = true

    private let recipes = RecipeLibrary.all()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                dropZone
                targetPicker

                ForEach(Recipe.Category.allCases, id: \.self) { category in
                    let entries = recipes.filter { $0.category == category }
                    if !entries.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(title(for: category)).font(.title3.weight(.semibold))
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12, alignment: .top)], spacing: 12) {
                                ForEach(entries) { recipe in
                                    RecipeCard(recipe: recipe) { install(recipe) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(22)
        }
        .navigationTitle("Install Software")
    }

    private var targetPicker: some View {
        Picker("Install into", selection: $targetBottleID) {
            Text("A new bottle").tag(UUID?.none)
            Divider()
            ForEach(model.bottles) { bottle in
                Text(verbatim: bottle.name).tag(UUID?.some(bottle.id))
            }
        }
        .fixedSize()
        .help("Where the software goes")
    }

    private var dropZone: some View {
        HStack(spacing: 16) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("Have an installer or a portable .exe?").font(.headline)
                Text("Drop it anywhere in this window, or choose the file. A snapshot is saved first, so an install that goes wrong can be undone.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose File…") { model.chooseFileToRun(in: targetBottleID.flatMap(model.bottle(id:))) }
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }

    private func title(for category: Recipe.Category) -> LocalizedStringKey {
        switch category {
        case .store: "Game stores"
        case .productivity: "Productivity"
        case .utility: "Utilities"
        case .runtime: "Runtimes and fonts"
        }
    }

    private func install(_ recipe: Recipe) {
        Task {
            var bottle = targetBottleID.flatMap(model.bottle(id:))
            if bottle == nil {
                guard let engine = model.preferredEngine else { return }
                // Runtimes are additions to an existing bottle; a bottle of their own would be pointless.
                if recipe.category == .runtime, let current = model.bottles.first {
                    bottle = current
                } else {
                    var name = recipe.name
                    var counter = 2
                    while model.bottles.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                        name = "\(recipe.name) \(counter)"
                        counter += 1
                    }
                    bottle = await model.createBottle(name: name, windowsVersion: recipe.windowsVersion, engine: engine)
                }
            }
            guard let bottle else { return }
            model.install(recipe, into: bottle)
            model.sidebarSelection = .activity
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe
    let install: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(verbatim: recipe.name).font(.headline)
                    if recipe.tested {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .help("Tested on this project's Mac")
                    }
                }
                Text(verbatim: recipe.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes = recipe.notes {
                    Text(verbatim: notes).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Button("Install", action: install)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
    }

    private var symbol: String {
        switch recipe.category {
        case .store: "bag"
        case .productivity: "doc.richtext"
        case .utility: "wrench.and.screwdriver"
        case .runtime: "shippingbox"
        }
    }
}

/// Running tasks and Windows processes.
struct ActivityView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section("Tasks") {
                if model.tasks.isEmpty {
                    Text("Downloads and installations will appear here.").foregroundStyle(.secondary)
                }
                ForEach(model.tasks) { task in
                    TaskRow(task: task)
                }
            }

            Section("Windows processes") {
                if model.processes.isEmpty {
                    Text("Nothing is running.").foregroundStyle(.secondary)
                }
                ForEach(model.processes) { process in
                    HStack {
                        Text(verbatim: process.name).fontWeight(.medium)
                        Spacer()
                        Text(verbatim: String(format: "%.0f%% CPU", process.cpuPercent))
                            .monospacedDigit()
                            .foregroundStyle(process.cpuPercent > 80 ? .orange : .secondary)
                            .frame(width: 80, alignment: .trailing)
                        Text(process.residentBytes, format: .byteCount(style: .memory))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)
                        Button {
                            kill(process.pid, SIGKILL)
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Force quit this process")
                    }
                    .help(Text(verbatim: process.path))
                }
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button("Clear Finished") { model.clearFinishedTasks() }
                    .disabled(model.tasks.allSatisfy { $0.state == .running })
            }
        }
    }
}

struct TaskRow: View {
    let task: ActivityTask

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(verbatim: task.title).fontWeight(.medium)
                Spacer()
                switch task.state {
                case .running:
                    if let fraction = task.fraction {
                        Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit().foregroundStyle(.secondary)
                    }
                case .finished:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .failed:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            if case .failed(let message) = task.state {
                Text(verbatim: message).font(.caption).foregroundStyle(.orange).lineLimit(4)
            } else {
                Text(verbatim: task.detail).font(.caption).foregroundStyle(.secondary)
            }
            if task.state == .running {
                if let fraction = task.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
