import GroveKit
import SwiftUI

struct RepoDetailView: View {
    let repo: RepoSnapshot
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(repo.entries) { entry in
                    WorktreeRow(entry: entry, repo: repo)
                }
            } header: {
                header
            }
        }
        .listStyle(.inset)
        .overlay {
            if let error = repo.error {
                ContentUnavailableView(
                    "Lecture impossible", systemImage: "exclamationmark.triangle", description: Text(error))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name).font(.title2.weight(.semibold))
                Text(repo.url.path(percentEncoded: false)).font(.caption).foregroundStyle(.secondary)
                Text(
                    "\(repo.worktreeCountLabel) · \(formattedSize(model.totalSize(of: repo))) au total"
                )
                .font(.callout).foregroundStyle(.secondary)
                if let problem = model.pullRequestProblems[repo.id] {
                    Label("PR/MR indisponibles", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                        .help(problem)
                }
            }
            Spacer()
            HStack(spacing: 2) {
                if let forge = repo.remote?.forge, let url = repo.remote?.webURL {
                    WebButton(forge: forge, url: url)
                }
                IconButton(symbol: "terminal", help: "Ouvrir le dépôt dans le terminal") {
                    model.openTerminal(at: repo.url.path)
                }
                IconButton(
                    symbol: model.settings.pinnedRepos.contains(repo.id) ? "pin.fill" : "pin",
                    help: "Épingler (en tête de liste et dans la barre de menus)"
                ) {
                    model.settings.togglePin(repo.id)
                }
                .accessibilityLabel("Épingler le dépôt")
            }
        }
        .buttonStyle(.borderless)
        .textCase(nil)
        .padding(.bottom, 6)
    }
}
