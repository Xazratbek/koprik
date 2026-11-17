import AppKit
import KoprikKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, engines, graphics, updates, about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .engines: "Engines"
        case .graphics: "Graphics"
        case .updates: "Updates"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .engines: "engine.combustion"
        case .graphics: "cube.transparent"
        case .updates: "arrow.down.circle"
        case .about: "info.circle"
        }
    }
}

/// Settings live inside the main window, as a page reached from the sidebar.
/// Ko'prik deliberately has one window: nothing opens beside or over it.
struct SettingsPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            Picker("Section", selection: $model.settingsTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.systemImage).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 560)
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 6)

            Group {
                switch model.settingsTab {
                case .general: GeneralSettingsPane()
                case .engines: EnginesSettingsPane()
                case .graphics: GraphicsSettingsPane()
                case .updates: UpdatesSettingsPane()
                case .about: AboutSettingsPane()
                }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
    }
}

private extension View {
    /// The three modifiers every settings pane needs for the grouped, glass-friendly look.
    func settingsPaneStyle() -> some View {
        formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, 8, for: .scrollContent)
    }
}

struct GeneralSettingsPane: View {
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @AppStorage("AppleLanguagesChoice") private var language = "system"

    var body: some View {
        Form {
            Section("Interface") {
                Toggle(isOn: $showMenuBarExtra) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show in the menu bar")
                        Text("Quick access to recent programs, and a way to stop everything.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Language", selection: $language) {
                    Text("Same as macOS").tag("system")
                    Text(verbatim: "English").tag("en")
                    Text(verbatim: "O'zbekcha").tag("uz")
                    Text(verbatim: "Русский").tag("ru")
                }
                .onChange(of: language) { _, value in
                    if value == "system" {
                        UserDefaults.standard.removeObject(forKey: "AppleLanguages")
                    } else {
                        UserDefaults.standard.set([value], forKey: "AppleLanguages")
                    }
                }
                Text("A language change takes effect the next time Ko'prik starts.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Storage") {
                LabeledContent("Data folder") {
                    Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.default.root) }
                }
                LabeledContent("App launchers") {
                    Button("Show in Finder") {
                        try? FileManager.default.createDirectory(at: AppLauncherBuilder.defaultFolder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(AppLauncherBuilder.defaultFolder)
                    }
                }
                LabeledContent("Download cache") {
                    Button("Clear") {
                        try? FileManager.default.removeItem(at: AppPaths.default.cache)
                        try? AppPaths.default.ensureDirectories()
                    }
                }
            }
        }
        .settingsPaneStyle()
    }
}

struct EnginesSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                if model.engines.isEmpty {
                    Text("No engine installed.").foregroundStyle(.secondary)
                }
                ForEach(model.engines) { engine in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: engine.name).fontWeight(.medium)
                            Spacer()
                            let users = model.bottles.count { $0.config.engineID == engine.id }
                            Text("\(users) bottles").foregroundStyle(.secondary)
                            Button(role: .destructive) {
                                Task { await model.removeEngine(engine) }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(users > 0)
                        }
                        Text(verbatim: ([engine.manifest.wineVersion ?? ""] + engine.manifest.components.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" })
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Installed")
            } footer: {
                Text("Each bottle stays on the engine it was created with, so trying a new engine never breaks bottles that work.")
            }

            Section("Add") {
                engineRow(
                    "Gaming engine",
                    detail: "Wine with CrossOver's patches, DXMT, DXVK and MoltenVK. The only kind that can host D3DMetal. 480 MB.",
                    source: .recommendedGaming
                )
                engineRow(
                    "Plain Wine",
                    detail: "Upstream Wine from the Gcenx builds. A fallback for ordinary applications.",
                    source: .recommendedPlain
                )
                Button("Import from Disk…") { importEngine() }
            }
        }
        .settingsPaneStyle()
    }

    private func engineRow(_ title: LocalizedStringKey, detail: LocalizedStringKey, source: EngineSource) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if model.engines.contains(where: { $0.id == source.defaultID }) {
                Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly)
            } else {
                Button("Download") { model.installEngine(source) }
            }
        }
    }

    private func importEngine() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = String(localized: "Choose a Wine folder or archive")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                _ = try await model.engineStore.importLocal(at: url)
                await model.reload()
            } catch {
                model.present(error)
            }
        }
    }
}

struct GraphicsSettingsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            ForEach(model.engines) { engine in
                let capabilities = Graphics.capabilities(of: engine)
                Section {
                    capabilityRow("DXMT", detail: "Direct3D 10/11 to Metal. The default for most games.", available: capabilities.dxmt)
                    capabilityRow("DXVK", detail: "Direct3D 10/11 to Vulkan over MoltenVK. Used for store launchers.", available: capabilities.dxvk)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "D3DMetal")
                            Text("Apple's Direct3D 11/12 layer from the Game Porting Toolkit. Needed for DirectX 12 games.")
                                .font(.caption).foregroundStyle(.secondary)
                            if capabilities.d3dmetal, let version = GPTKImporter.version(in: engine) {
                                Text("Version \(version)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if capabilities.d3dmetal {
                            Button("Remove") {
                                try? GPTKImporter.remove(from: engine)
                                Task { await model.reload() }
                            }
                        } else if engine.manifest.d3dmetalCapable {
                            Button("Import…") { importToolkit(into: engine) }
                        } else {
                            Text("Not supported").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(verbatim: engine.name)
                }
            }

            Section {
                Link("Download the Game Porting Toolkit from Apple", destination: URL(string: "https://developer.apple.com/games/game-porting-toolkit/")!)
            } footer: {
                Text("Apple does not allow the toolkit to be redistributed, so Ko'prik cannot download it for you. Sign in with a free Apple developer account, download the disk image, then choose it with Import.")
            }
        }
        .settingsPaneStyle()
    }

    private func capabilityRow(_ name: String, detail: LocalizedStringKey, available: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(available ? .green : .secondary)
        }
    }

    private func importToolkit(into engine: Engine) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = String(localized: "Choose the Game Porting Toolkit disk image or folder")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.importGPTK(from: url, into: engine)
    }
}

struct UpdatesSettingsPane: View {
    @ObservedObject private var updater = UpdaterManager.shared

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                .disabled(!updater.isConfigured)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } header: {
                Text("Ko'prik")
            } footer: {
                if !updater.isConfigured {
                    Text("Updates are not set up in this build: no update feed and signing key were configured. See docs/RELIZ.md.")
                }
            }
        }
        .settingsPaneStyle()
    }
}

struct AboutSettingsPane: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version") { Text(verbatim: version) }
            } header: {
                Text("Ko'prik")
            } footer: {
                Text("Ko'prik runs Windows software through Wine, which is free software under the LGPL. DXMT, DXVK and MoltenVK are open source. Ko'prik contains no code from CrossOver. Kernel-level anti-cheat does not work under Wine.")
            }
            Section("Open-source components") {
                Link("Wine", destination: URL(string: "https://www.winehq.org")!)
                Link("winecx-gptk engine builds", destination: URL(string: "https://github.com/frankea/winecx-gptk")!)
                Link("DXMT", destination: URL(string: "https://github.com/3Shain/dxmt")!)
                Link("DXVK-macOS", destination: URL(string: "https://github.com/Gcenx/DXVK-macOS")!)
                Link("MoltenVK", destination: URL(string: "https://github.com/KhronosGroup/MoltenVK")!)
                Link("winetricks", destination: URL(string: "https://github.com/Winetricks/winetricks")!)
                Link("Sparkle", destination: URL(string: "https://sparkle-project.org")!)
            }
        }
        .settingsPaneStyle()
    }
}
