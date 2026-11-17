import KoprikKit
import SwiftUI

/// Epic Games and GOG libraries, installed and launched without the stores' own launchers.
struct StoreView: View {
    @Environment(AppModel.self) private var model
    let store: StoreGame.Store

    @State private var code = ""
    @State private var connecting = false
    @State private var targetBottleID: UUID?

    private var title: String { store == .epic ? "Epic Games" : "GOG" }
    private var state: AppModel.StoreState { model.storeStates[store] ?? AppModel.StoreState() }

    var body: some View {
        Group {
            if !state.loggedIn {
                signIn
            } else if state.loading && state.games.isEmpty {
                ProgressView("Loading your library…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                library
            }
        }
        .navigationTitle(Text(verbatim: title))
        .task(id: store) { await model.refreshStore(store) }
    }

    private var signIn: some View {
        VStack(spacing: 18) {
            Image(systemName: store == .epic ? "e.square.fill" : "g.square.fill")
                .font(.system(size: 54))
                .foregroundStyle(Color.accentColor)
            Text("Sign in to \(title)").font(.title2.weight(.semibold))
            Text(store == .epic
                 ? "Sign in on the page that opens. It then shows a short JSON text; copy the authorizationCode value (or the whole text) and paste it here."
                 : "Sign in on the page that opens. When it shows a blank page, copy the whole address from the address bar and paste it here.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Button("Open Sign-in Page") {
                NSWorkspace.shared.open(store == .epic ? EpicStore.loginURL : GOGStore.loginURL)
            }
            .buttonStyle(.borderedProminent)
            HStack {
                TextField("Code or address", text: $code)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 360)
                    .onSubmit(connect)
                Button("Connect", action: connect)
                    .disabled(code.trimmingCharacters(in: .whitespaces).isEmpty || connecting)
                if connecting { ProgressView().controlSize(.small) }
            }
            Text("Ko'prik keeps the sign-in on this Mac, in its own data folder. It is never sent anywhere but \(title).")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var library: some View {
        List {
            Section {
                Picker("Install into", selection: $targetBottleID) {
                    Text("A new \(title) bottle").tag(UUID?.none)
                    ForEach(model.bottles) { bottle in
                        Text(verbatim: bottle.name).tag(UUID?.some(bottle.id))
                    }
                }
                .fixedSize()
            } footer: {
                if let error = state.error {
                    Text(verbatim: error).foregroundStyle(.orange)
                }
            }
            Section("\(state.games.count) games") {
                ForEach(state.games) { game in
                    HStack(spacing: 12) {
                        AsyncImage(url: game.coverURL) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Image(systemName: "gamecontroller").foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 58)
                        .clipShape(.rect(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: game.title).fontWeight(.medium)
                            if game.isInstalled {
                                Text("Installed").font(.caption).foregroundStyle(.green)
                            }
                        }
                        Spacer()
                        if let item = model.libraryItem(for: game) {
                            Button("Play") { model.launch(item) }
                                .buttonStyle(.borderedProminent)
                        } else if model.installingStoreGames.contains(game.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Install") { model.installStoreGame(game, into: targetBottleID) }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Refresh") { Task { await model.refreshStore(store) } }
                    Button("Sign Out", role: .destructive) { Task { await model.signOut(of: store) } }
                } label: {
                    Label("Store", systemImage: "ellipsis.circle")
                }
            }
        }
    }

    private func connect() {
        connecting = true
        Task {
            await model.signIn(to: store, code: code)
            connecting = false
            code = ""
        }
    }
}
