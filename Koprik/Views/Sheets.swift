import KoprikKit
import SwiftUI

struct NewBottleSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var windowsVersion = WindowsVersion.win10
    @State private var engineID = ""
    @State private var creating = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Games, Office, …"))
                    Picker("Windows version", selection: $windowsVersion) {
                        ForEach(WindowsVersion.allCases, id: \.self) { Text(verbatim: $0.displayName).tag($0) }
                    }
                    Picker("Engine", selection: $engineID) {
                        ForEach(model.engines) { Text(verbatim: $0.name).tag($0.id) }
                    }
                } header: {
                    Text("New Bottle")
                } footer: {
                    Text("A bottle is a separate Windows environment with its own C: drive. Keeping unrelated software in separate bottles stops one from breaking another.")
                }
            }
            .formStyle(.grouped)

            HStack {
                if creating {
                    ProgressView().controlSize(.small)
                    Text("The first bottle takes about a minute.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || engineID.isEmpty || creating)
            }
            .padding()
        }
        .frame(width: 460, height: 330)
        .onAppear { engineID = model.preferredEngine?.id ?? "" }
    }

    private func create() {
        guard let engine = model.engines.first(where: { $0.id == engineID }) else { return }
        creating = true
        Task {
            if let bottle = await model.createBottle(name: name.trimmingCharacters(in: .whitespaces), windowsVersion: windowsVersion, engine: engine) {
                model.sidebarSelection = .bottle(bottle.id)
                dismiss()
            }
            creating = false
        }
    }
}

struct RunCommandSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var command = ""
    private let suggestions = ["winecfg", "regedit", "taskmgr", "control", "cmd", "explorer", "notepad", "uninstaller", "winver", "dxdiag"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Run Command in \(bottle.name)").font(.headline)
            TextField("Command", text: $command, prompt: Text(verbatim: "winecfg"))
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
                .onSubmit(run)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button(suggestion) { command = suggestion }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Run", action: run)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func run() {
        let parts = ProgramArguments.split(command)
        guard let first = parts.first else { return }
        model.run(command: first, arguments: Array(parts.dropFirst()), in: bottle)
        dismiss()
    }
}

struct WinetricksSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var selected: Set<String> = []
    @State private var custom = ""

    var body: some View {
        VStack(spacing: 0) {
            List {
                let missing = Winetricks.missingTools()
                if !missing.isEmpty {
                    Label {
                        Text("Needs \(missing.joined(separator: ", ")). Install it in Terminal with: brew install \(missing.joined(separator: " "))")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Section("Components") {
                    ForEach(Winetricks.commonVerbs, id: \.verb) { entry in
                        Toggle(isOn: Binding(
                            get: { selected.contains(entry.verb) },
                            set: { if $0 { selected.insert(entry.verb) } else { selected.remove(entry.verb) } }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(verbatim: entry.title)
                                Text(verbatim: entry.verb).font(.caption.monospaced()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Other winetricks verbs") {
                    TextField("Verbs", text: $custom, prompt: Text(verbatim: "dxvk1103 quartz"))
                        .font(.body.monospaced())
                }
            }
            HStack {
                Text("Installs into \(bottle.name).").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Install") {
                    let verbs = selected.sorted() + ProgramArguments.split(custom)
                    model.runWinetricks(verbs, in: bottle)
                    model.sidebarSelection = .activity
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selected.isEmpty && custom.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 520, height: 560)
    }
}

struct SnapshotsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let bottle: Bottle

    @State private var snapshots: [BottleSnapshot] = []
    @State private var label = ""
    @State private var pendingRestore: BottleSnapshot?

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    HStack {
                        TextField("Label", text: $label, prompt: Text("Before installing mods"))
                        Button("Save Snapshot") {
                            Task {
                                await model.snapshot(bottle, label: label.isEmpty ? String(localized: "Manual snapshot") : label)
                                label = ""
                                await load()
                            }
                        }
                    }
                } footer: {
                    Text("A snapshot is a full copy of the bottle's C: drive and registry. Copies share disk space with the original until files change. Programs in the bottle are stopped first.")
                }

                Section("Saved") {
                    if snapshots.isEmpty {
                        Text("No snapshots yet.").foregroundStyle(.secondary)
                    }
                    ForEach(snapshots) { snapshot in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: snapshot.label)
                                Text(snapshot.createdAt, format: .dateTime.day().month().year().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") { pendingRestore = snapshot }
                            Button(role: .destructive) {
                                Task {
                                    try? await model.bottleStore.deleteSnapshot(bottle, snapshotID: snapshot.id)
                                    await load()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520, height: 460)
        .task { await load() }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } }),
            presenting: pendingRestore
        ) { snapshot in
            Button("Restore", role: .destructive) {
                Task {
                    await model.restore(bottle, snapshot: snapshot)
                    dismiss()
                }
            }
        } message: { _ in
            Text("Everything in the bottle changed since the snapshot will be lost. This cannot be undone.")
        }
    }

    private func load() async {
        snapshots = (try? await model.bottleStore.snapshots(of: bottle)) ?? []
    }
}

/// Type a few letters, press Return, play.
struct QuickLaunchSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var results: [LibraryItem] {
        let all = model.allItems.sorted {
            ($0.program.lastPlayed ?? .distantPast) > ($1.program.lastPlayed ?? .distantPast)
        }
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return Array((trimmed.isEmpty ? all : all.filter { $0.program.name.localizedCaseInsensitiveContains(trimmed) }).prefix(8))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Launch a program…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($focused)
                    .onSubmit { launch(highlighted) }
                    .onKeyPress(.downArrow) { highlighted = min(highlighted + 1, results.count - 1); return .handled }
                    .onKeyPress(.upArrow) { highlighted = max(highlighted - 1, 0); return .handled }
                    .onKeyPress(.escape) { dismiss(); return .handled }
            }
            .padding(16)
            Divider()
            VStack(spacing: 2) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                    HStack {
                        ProgramIcon(item: item, size: 26)
                        Text(verbatim: item.program.name)
                        Spacer()
                        Text(verbatim: item.bottle.name).foregroundStyle(.secondary).font(.callout)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(index == highlighted ? Color.accentColor.opacity(0.22) : .clear, in: .rect(cornerRadius: 8))
                    .contentShape(.rect)
                    .onTapGesture { launch(index) }
                }
                if results.isEmpty {
                    Text("No programs found").foregroundStyle(.secondary).padding()
                }
            }
            .padding(8)
        }
        .frame(width: 520)
        .onAppear { focused = true }
        .onChange(of: query) { highlighted = 0 }
    }

    private func launch(_ index: Int) {
        guard results.indices.contains(index) else { return }
        model.launch(results[index])
        dismiss()
    }
}

/// A launch log with the analyser's reading of it on top.
struct LogSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let log: LogReference

    @State private var text = ""
    @State private var summary = LogSummary()
    @State private var onlyErrors = false

    private var shownText: String {
        guard onlyErrors else { return text }
        return text.split(separator: "\n").filter { $0.contains("err:") || $0.localizedCaseInsensitiveContains("error") }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: log.title).font(.headline)
                    Text("\(summary.lineCount) lines, \(summary.errorLines) errors")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Errors only", isOn: $onlyErrors).toggleStyle(.switch).controlSize(.small)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([log.url]) }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()

            if !summary.findings.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(summary.findings) { finding in
                        FindingRow(finding: finding) { verb in
                            if let bottle = model.bottles.first(where: { log.url.path.hasPrefix($0.directory.path) }) {
                                model.runWinetricks([verb], in: bottle)
                                dismiss()
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
            Divider()
            ScrollView {
                Text(verbatim: shownText.isEmpty ? String(localized: "The log is empty.") : shownText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(.background.secondary)
        }
        .frame(width: 780, height: 600)
        .task {
            let url = log.url
            let loaded = await Task.detached(priority: .userInitiated) { () -> (String, LogSummary) in
                let data = (try? Data(contentsOf: url)) ?? Data()
                // Show the end of very large logs; that is where a failure is.
                let tail = data.count > 600_000 ? data.suffix(600_000) : data
                return (String(decoding: tail, as: UTF8.self), LogAnalyzer.analyze(fileAt: url))
            }.value
            text = loaded.0
            summary = loaded.1
        }
    }
}

struct FindingRow: View {
    let finding: LogFinding
    let installVerb: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: finding.severity == .error ? "xmark.octagon.fill" : finding.severity == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(finding.severity == .error ? .red : finding.severity == .warning ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: finding.title).fontWeight(.medium)
                Text(verbatim: finding.advice).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let verb = finding.suggestedVerb {
                Button("Install \(verb)") { installVerb(verb) }
            }
        }
        .padding(10)
        .background(.background.secondary, in: .rect(cornerRadius: 10))
    }
}

/// First run: check Rosetta, get an engine.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private var engineTask: ActivityTask? {
        model.tasks.first { $0.state == .running }
    }

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Ko'prik").font(.largeTitle.weight(.semibold))
            Text("Run Windows programs and games on your Mac.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 16) {
                step(
                    done: model.rosettaAvailable,
                    title: "Rosetta 2",
                    detail: model.rosettaAvailable
                        ? "Installed. It lets Intel code, including Wine, run on Apple silicon."
                        : "Needed to run Wine. Install it in Terminal with: softwareupdate --install-rosetta --agree-to-license"
                )
                step(
                    done: !model.engines.isEmpty,
                    title: "Wine engine",
                    detail: "Wine with CrossOver's open-source patches, DXMT and DXVK. About 480 MB to download, 1.3 GB on disk."
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: 16))

            if let engineTask {
                VStack(spacing: 6) {
                    if let fraction = engineTask.fraction {
                        ProgressView(value: fraction)
                    } else {
                        ProgressView().progressViewStyle(.linear)
                    }
                    Text(verbatim: engineTask.detail).font(.caption).foregroundStyle(.secondary)
                }
            } else if model.engines.isEmpty {
                Button("Download Engine") { model.installEngine(.recommendedGaming) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!model.rosettaAvailable)
            }
            Button("Check Again") { Task { await model.reload() } }
                .buttonStyle(.link)
        }
        .padding(34)
        .frame(width: 520)
    }

    private func step(done: Bool, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
