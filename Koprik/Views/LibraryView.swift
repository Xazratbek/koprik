import KoprikKit
import SwiftUI

/// A grid of program cards. Clicking selects, double-clicking launches.
struct LibraryGrid: View {
    @Environment(AppModel.self) private var model
    let items: [LibraryItem]
    var emptyTitle: LocalizedStringKey = "Nothing here yet"
    var emptyMessage: LocalizedStringKey = ""

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18, alignment: .top)]

    var body: some View {
        if items.isEmpty {
            ContentUnavailableView {
                Label(model.searchText.isEmpty ? emptyTitle : "No matches", systemImage: model.searchText.isEmpty ? "square.grid.2x2" : "magnifyingglass")
            } description: {
                Text(model.searchText.isEmpty ? emptyMessage : "Try another search.")
            } actions: {
                if model.searchText.isEmpty {
                    Button("Run a Windows File…") { model.chooseFileToRun() }
                    Button("Install Software") { model.sidebarSelection = .install }
                }
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 22) {
                    ForEach(items) { item in
                        ProgramCard(item: item)
                    }
                }
                .padding(22)
            }
            .contentShape(.rect)
            .onTapGesture { model.selectedItemID = nil }
        }
    }
}

struct ProgramCard: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    @State private var hovering = false
    @State private var cover: NSImage?

    private var isSelected: Bool { model.selectedItemID == item.id }
    private var isRunning: Bool { model.isRunning(item) }
    private var isLaunching: Bool { model.launching.contains(item.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artwork
                .frame(height: 200)
                .frame(maxWidth: .infinity)
                .clipShape(.rect(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .topTrailing) { badges }
                .overlay { playOverlay }
                .shadow(color: .black.opacity(hovering ? 0.28 : 0.12), radius: hovering ? 14 : 5, y: hovering ? 8 : 3)
                .scaleEffect(hovering ? 1.025 : 1)
                .animation(.spring(duration: 0.28), value: hovering)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.program.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 5) {
                    if isRunning {
                        Image(systemName: "circle.fill").font(.system(size: 6)).foregroundStyle(.green)
                        Text("Running").foregroundStyle(.green)
                    } else {
                        Text(verbatim: item.bottle.name)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { model.launch(item) }
        .simultaneousGesture(TapGesture().onEnded {
            model.selectedItemID = item.id
            model.showInspector = true
        })
        .contextMenu { ProgramMenu(item: item) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: item.program.name))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Play")) { model.launch(item) }
        .task(id: item.id) {
            if let appID = item.program.steamAppID {
                cover = await IconProvider.shared.artwork(forSteamApp: appID)
            }
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let cover {
            Image(nsImage: cover)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.06)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .background(.background.secondary)
                ProgramIcon(item: item, size: 76)
            }
        }
    }

    @ViewBuilder
    private var badges: some View {
        HStack(spacing: 4) {
            if model.compatibility[item.id]?.isBlocked == true {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundStyle(.white, .red)
                    .help("Anti-cheat blocks this game under Wine")
            }
            if item.program.favorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
        .font(.callout)
        .padding(8)
        .shadow(radius: 2)
    }

    @ViewBuilder
    private var playOverlay: some View {
        if isLaunching {
            ProgressView()
                .controlSize(.large)
                .padding(18)
                .glassEffect(.regular, in: .circle)
        } else if hovering {
            Button {
                model.launch(item)
            } label: {
                Image(systemName: "play.fill")
                    .font(.title2)
                    .frame(width: 52, height: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .help("Play")
            .transition(.scale(scale: 0.8).combined(with: .opacity))
        }
    }
}

/// Actions on a program, shared by the card's context menu and the inspector.
struct ProgramMenu: View {
    @Environment(AppModel.self) private var model
    let item: LibraryItem

    var body: some View {
        Button("Play", systemImage: "play.fill") { model.launch(item) }
        Menu("Play With", systemImage: "slider.horizontal.3") {
            ForEach(GraphicsBackend.allCases, id: \.self) { backend in
                Button(backend.displayName) { model.launch(item, overrides: LaunchSettings(backend: backend)) }
            }
            Divider()
            Button("Metal Performance HUD") { model.launch(item, overrides: LaunchSettings(metalHUD: true)) }
            Button("DXVK Frame Rate HUD") { model.launch(item, overrides: LaunchSettings(dxvkHUD: .fps)) }
        }
        Divider()
        Button(item.program.favorite ? "Remove from Favorites" : "Add to Favorites", systemImage: "star") {
            Task { await model.toggleFavorite(item) }
        }
        Button("Settings", systemImage: "sidebar.right") {
            model.selectedItemID = item.id
            model.showInspector = true
        }
        Button("Create App Launcher", systemImage: "app.badge") { model.createLauncher(for: item) }
        Button("Show in Finder", systemImage: "folder") {
            let url = item.program.executableURL(in: item.bottle) ?? URL(fileURLWithPath: item.program.location)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        Divider()
        Button("Hide from Library", systemImage: "eye.slash") { Task { await model.hide(item) } }
    }
}
