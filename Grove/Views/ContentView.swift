import AppKit
import GroveKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var search = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle("Grove")
        .searchable(text: $search, placement: .sidebar, prompt: "Filtrer les dépôts")
        .toolbar {
            ToolbarItem {
                Button {
                    Task { await model.reload() }
                } label: {
                    if model.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Actualiser", systemImage: "arrow.clockwise")
                    }
                }
                .keyboardShortcut("r")
                .help("Actualiser (⌘R)")
            }
        }
        .sheet(item: $model.removal) { RemovalSheet(review: $0) }
        .alert(item: $model.notice) { Alert(title: Text($0.title), message: Text($0.message)) }
        .task { await model.start() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) {
            _ in
            Task { await model.reloadIfStale() }
        }
    }

    private var filtered: [RepoSnapshot] {
        let repos = model.sidebarRepos
        return search.isEmpty ? repos : repos.filter { $0.name.localizedStandardContains(search) }
    }

    @ViewBuilder private var sidebar: some View {
        if model.settings.scanRoots.isEmpty {
            ContentUnavailableView {
                Label("Aucun dossier", systemImage: "folder.badge.plus")
            } description: {
                Text("Choisis le dossier qui contient tes projets.")
            } actions: {
                Button("Choisir un dossier…") { chooseFolder() }
            }
        } else {
            List(filtered, selection: $selection) { repo in
                RepoSidebarRow(repo: repo).tag(repo.id)
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .overlay {
                if model.snapshots.isEmpty && !model.isLoading {
                    ContentUnavailableView(
                        "Aucun dépôt git", systemImage: "questionmark.folder",
                        description: Text("Rien trouvé dans les dossiers analysés."))
                }
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let repo = model.snapshots.first(where: { $0.id == selection }) {
            RepoDetailView(repo: repo)
        } else {
            ContentUnavailableView("Sélectionne un dépôt", systemImage: "arrow.triangle.branch")
        }
    }

    private func chooseFolder() {
        if let path = FolderPicker.choose(), !model.settings.scanRoots.contains(path) {
            model.settings.scanRoots.append(path)
            Task { await model.reload() }
        }
    }
}

struct RepoSidebarRow: View {
    let repo: RepoSnapshot
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if model.settings.pinnedRepos.contains(repo.id) {
                Image(systemName: "pin.fill").font(.caption).foregroundStyle(.tint).accessibilityLabel(
                    "Épinglé")
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(repo.name).lineLimit(1)
                Text(repo.worktreeCountLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(formattedSize(model.totalSize(of: repo)))
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .contextMenu {
            Button(model.settings.pinnedRepos.contains(repo.id) ? "Désépingler" : "Épingler") {
                model.settings.togglePin(repo.id)
            }
            Button("Ouvrir dans le terminal") { model.openTerminal(at: repo.url.path) }
        }
    }
}

enum FolderPicker {
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Analyser"
        panel.message = "Dossier à analyser pour y trouver des dépôts git"
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}
