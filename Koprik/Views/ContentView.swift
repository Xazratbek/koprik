import KoprikKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } detail: {
            DetailView()
        }
        // The inspector describes a program, so it steps aside on pages that show none.
        .inspector(isPresented: Binding(
            get: { model.showInspector && model.selectionShowsPrograms },
            set: { model.showInspector = $0 }
        )) {
            InspectorView()
                .inspectorColumnWidth(min: 290, ideal: 330, max: 440)
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search programs"))
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !model.runningBottles.isEmpty {
                    Button {
                        Task { await model.stopEverything() }
                    } label: {
                        Label("Stop Everything", systemImage: "stop.circle")
                    }
                    .help("Stop every running Windows program")
                }
                Menu {
                    Button("New Bottle…", systemImage: "plus.square.on.square") { model.sheet = .newBottle }
                    Button("Run a Windows File…", systemImage: "doc.badge.gearshape") { model.chooseFileToRun() }
                    Button("Install Software…", systemImage: "square.and.arrow.down") { model.sidebarSelection = .install }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .help("Create a bottle, run a file or install software")

                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide settings for the selection")
            }
        }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .newBottle: NewBottleSheet()
            case .runCommand(let bottle): RunCommandSheet(bottle: bottle)
            case .winetricks(let bottle): WinetricksSheet(bottle: bottle)
            case .snapshots(let bottle): SnapshotsSheet(bottle: bottle)
            case .palette: QuickLaunchSheet()
            }
        }
        .sheet(item: $model.presentedLog) { log in
            LogSheet(log: log)
        }
        .sheet(isPresented: .constant(model.needsOnboarding)) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(verbatim: alert.title), message: Text(verbatim: alert.message), dismissButton: .default(Text("OK")))
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.filter(\.isFileURL).forEach(model.open(file:))
            return true
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebarSelection) {
            Section("Library") {
                ForEach(LibraryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .badge(filter == .all ? model.allItems.count : 0)
                        .tag(SidebarItem.library(filter))
                }
            }

            Section("Bottles") {
                ForEach(model.bottles) { bottle in
                    Label {
                        Text(verbatim: bottle.name)
                    } icon: {
                        Image(systemName: (bottle.config.isolation ?? .off).isOn ? "lock.shield" : (model.runningBottles.contains(bottle.id) ? "cylinder.split.1x2.fill" : "cylinder.split.1x2"))
                            .foregroundStyle(model.runningBottles.contains(bottle.id) ? Color.green : Color.accentColor)
                    }
                    .tag(SidebarItem.bottle(bottle.id))
                    .contextMenu { BottleMenu(bottle: bottle) }
                }
                Button {
                    model.sheet = .newBottle
                } label: {
                    Label("New Bottle…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Section("Stores") {
                Label("Epic Games", systemImage: "e.square")
                    .tag(SidebarItem.store(.epic))
                Label { Text(verbatim: "GOG") } icon: { Image(systemName: "g.square") }
                    .tag(SidebarItem.store(.gog))
            }

            Section("Tools") {
                Label("Install Software", systemImage: "square.and.arrow.down")
                    .tag(SidebarItem.install)
                Label("Activity", systemImage: "waveform.path.ecg")
                    .badge(model.activeTaskCount)
                    .tag(SidebarItem.activity)
                Label("Controllers", systemImage: "gamecontroller")
                    .tag(SidebarItem.controllers)
                Label("Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Ko'prik")
    }
}

/// Actions on a bottle, shared by the sidebar's context menu and the bottle page.
struct BottleMenu: View {
    @Environment(AppModel.self) private var model
    let bottle: Bottle

    var body: some View {
        Button("Run a Windows File…", systemImage: "doc.badge.gearshape") { model.chooseFileToRun(in: bottle) }
        Button("Run Command…", systemImage: "terminal") { model.sheet = .runCommand(bottle) }
        Button("Install Components…", systemImage: "shippingbox") { model.sheet = .winetricks(bottle) }
        Divider()
        Button("Open C: Drive", systemImage: "externaldrive") { NSWorkspace.shared.open(bottle.driveC) }
        Button("Snapshots…", systemImage: "clock.arrow.circlepath") { model.sheet = .snapshots(bottle) }
        Button("Back Up Saves", systemImage: "externaldrive.badge.timemachine") { model.backUpSaves(of: bottle) }
        Button("Restore Saves…", systemImage: "arrow.uturn.backward.circle") { model.restoreSaves(of: bottle) }
        Button("Duplicate", systemImage: "plus.square.on.square") { Task { await model.duplicate(bottle) } }
        Divider()
        Button("Stop All Programs", systemImage: "stop.circle") { Task { await model.stopAll(in: bottle) } }
            .disabled(!model.runningBottles.contains(bottle.id))
        Button("Move to Trash", systemImage: "trash", role: .destructive) { Task { await model.delete(bottle) } }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.sidebarSelection ?? .library(.all) {
        case .library(let filter):
            LibraryGrid(items: model.items(for: filter), emptyTitle: "Nothing here yet", emptyMessage: emptyMessage(for: filter))
                .navigationTitle(filter.title)
        case .bottle(let id):
            if let bottle = model.bottle(id: id) {
                BottleView(bottle: bottle)
            } else {
                ContentUnavailableView("Bottle not found", systemImage: "cylinder.split.1x2")
            }
        case .install:
            InstallView()
        case .activity:
            ActivityView()
        case .settings:
            SettingsPage()
        case .store(let store):
            StoreView(store: store)
        case .controllers:
            ControllersView()
        }
    }

    private func emptyMessage(for filter: LibraryFilter) -> LocalizedStringKey {
        switch filter {
        case .favorites: "Mark a program with the star to keep it here."
        case .recent: "Programs you run will show up here."
        case .games: "Install Steam from Install Software, then your games appear here."
        case .all, .apps: "Drop a Windows .exe anywhere in this window, or install software from the sidebar."
        }
    }
}
