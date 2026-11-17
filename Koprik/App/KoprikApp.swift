import AppKit
import KoprikKit
import SwiftUI

@main
struct KoprikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        Window("Ko'prik", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 580)
                .task { model.start() }
        }
        .defaultSize(width: 1180, height: 760)
        .commands { AppCommands(model: model) }

        MenuBarExtra("Ko'prik", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill", isInserted: $showMenuBarExtra) {
            MenuBarView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UpdaterManager.shared.start()
    }

    /// Files opened from Finder or dropped on the Dock icon, and `koprik://` links.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            let model = AppModel.shared
            if !model.isLoaded { await model.reload() }
            urls.forEach(model.open(url:))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Games keep running after the window closes; the menu bar item stays as the way back in.
        !UserDefaults.standard.bool(forKey: "showMenuBarExtra")
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { model.showSettings() }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { UpdaterManager.shared.checkForUpdates() }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Bottle…") { model.sheet = .newBottle }
                .keyboardShortcut("n", modifiers: .command)
            Button("Run a Windows File…") { model.chooseFileToRun() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Run Command…") {
                if let bottle = model.currentBottle ?? model.bottles.first { model.sheet = .runCommand(bottle) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model.bottles.isEmpty)
        }
        CommandMenu("Bottle") {
            Button("Quick Launch…") { model.sheet = .palette }
                .keyboardShortcut("k", modifiers: .command)
            Divider()
            Button("Stop Everything") { Task { await model.stopEverything() } }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(model.runningBottles.isEmpty)
            Button("Refresh Library") { Task { await model.reload() } }
                .keyboardShortcut("r", modifiers: .command)
        }
        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}

/// The panel behind the menu bar icon: what is running, what was played last.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            let running = model.allItems.filter(model.isRunning)
            if !running.isEmpty {
                Text("Running").font(.caption).foregroundStyle(.secondary)
                ForEach(running) { item in
                    Label { Text(verbatim: item.program.name) } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(.green).imageScale(.small)
                    }
                }
                Divider()
            }

            let recent = model.items(for: .recent).prefix(6)
            if recent.isEmpty {
                Text("Nothing played yet").foregroundStyle(.secondary)
            } else {
                Text("Recently Played").font(.caption).foregroundStyle(.secondary)
                ForEach(recent) { item in
                    Button {
                        model.launch(item)
                    } label: {
                        HStack {
                            ProgramIcon(item: item, size: 20)
                            Text(verbatim: item.program.name).lineLimit(1)
                            Spacer()
                            Image(systemName: "play.fill").foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Button("Open Ko'prik") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                Button("Stop Everything") { Task { await model.stopEverything() } }
                    .disabled(model.runningBottles.isEmpty)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
