import GroveKit
import SwiftUI

/// Compact list for the menu bar window: up to the chosen number of repos, each with its worktrees.
struct MenuBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    // A bare ScrollView has no ideal height in a MenuBarExtra window and collapses: measure the content.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.menuBarRepos.isEmpty {
                        Text(
                            model.settings.scanRoots.isEmpty
                                ? "Choisis un dossier dans Grove." : "Aucun dépôt trouvé."
                        )
                        .foregroundStyle(.secondary)
                    }
                    ForEach(model.menuBarRepos) { repo in
                        MenuBarRepo(repo: repo)
                    }
                }
                .padding(12)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .frame(height: min(contentHeight, 520))
            Divider()
            HStack {
                Button("Ouvrir Grove") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: "Actualiser") { Task { await model.reload() } }
                Button("Quitter") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(10)
        }
        .frame(width: 360)
        .task {
            await model.start()
            await model.reloadIfStale()
        }
    }
}

private struct MenuBarRepo: View {
    let repo: RepoSnapshot
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(repo.name).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(formattedSize(model.totalSize(of: repo))).font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let forge = repo.remote?.forge, let url = repo.remote?.webURL {
                    WebButton(forge: forge, url: url, size: .menuBar)
                }
                IconButton(symbol: "terminal", help: "Ouvrir le dépôt dans le terminal", size: .menuBar) {
                    model.openTerminal(at: repo.url.path)
                }
            }
            ForEach(repo.entries.filter { !$0.worktree.isMain }) { entry in
                HStack(spacing: 6) {
                    Circle().fill(entry.status.tint).frame(width: 7, height: 7).accessibilityHidden(true)
                    if let origin = entry.worktree.origin { OriginIcon(origin: origin) }
                    Text(entry.worktree.title).font(.caption).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if let forge = repo.remote?.forge, let target = model.webTarget(for: entry, in: repo),
                        let state = target.request?.state
                    {
                        WebButton(forge: forge, url: target.url, state: state, size: .menuBar)
                    }
                    IconButton(symbol: "terminal", help: "Ouvrir dans le terminal", size: .menuBar) {
                        model.openTerminal(at: entry.worktree.path)
                    }
                    IconButton(symbol: "sparkle", help: "Ouvrir Claude Code ici", size: .menuBar) {
                        model.openClaude(at: entry.worktree.path)
                    }
                }
                .padding(.leading, 10)
            }
        }
    }
}
