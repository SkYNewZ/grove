import GroveKit
import SwiftUI

struct WorktreeRow: View {
    let entry: WorktreeEntry
    let repo: RepoSnapshot
    @Environment(AppModel.self) private var model
    @State private var showExplanation = false

    private var worktree: Worktree { entry.worktree }
    private var blockReason: String? { RemovalError.blockReason(for: entry.status) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(worktree.title).font(.body).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    if let origin = worktree.origin { OriginIcon(origin: origin) }
                    Text(worktree.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            StatusBadge(status: entry.status)
            Text(formattedSize(model.size(of: entry, in: repo)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(minWidth: 62, alignment: .trailing)
            actions
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Afficher dans le Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
            }
            Button("Copier le chemin") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path, forType: .string)
            }
        }
    }

    private var symbol: String {
        if worktree.isMain { return "house" }
        return worktree.isDetached ? "smallcircle.filled.circle" : "arrow.triangle.branch"
    }

    @ViewBuilder private var actions: some View {
        let exists = entry.status != .prunable
        HStack(spacing: 4) {
            if let forge = repo.remote?.forge, let target = model.webTarget(for: entry, in: repo) {
                WebButton(forge: forge, url: target.url, state: target.request?.state)
            }
            IconButton(symbol: "terminal", help: "Ouvrir dans le terminal", enabled: exists) {
                model.openTerminal(at: worktree.path)
            }
            IconButton(symbol: "sparkle", help: "Ouvrir Claude Code ici", enabled: exists) {
                model.openClaude(at: worktree.path)
            }
            IconButton(
                symbol: "wand.and.stars", help: "Expliquer ce worktree (IA)", enabled: !worktree.isMain
            ) {
                model.explain(entry, in: repo)
                showExplanation = true
            }
            .popover(isPresented: $showExplanation, arrowEdge: .bottom) {
                ExplainView(entry: entry, repo: repo)
            }
            if model.busyWorktrees.contains(entry.id) {
                ProgressView().controlSize(.small).frame(width: 22)
            } else {
                IconButton(
                    symbol: "trash",
                    help: blockReason.map { "Suppression impossible : \($0)" } ?? "Mettre à la Corbeille",
                    enabled: blockReason == nil
                ) {
                    model.beginRemoval(entry, in: repo)
                }
            }
        }
    }
}

struct StatusBadge: View {
    let status: WorktreeStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(status.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(status.tint)
            .help(help)
    }

    private var help: String {
        if case .wip(let changes) = status { return "\(changes.count) fichier(s) modifié(s) ou non suivi(s)" }
        return RemovalError.blockReason(for: status).map { "Non supprimable : \($0)" } ?? status.label
    }
}
