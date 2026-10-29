import GroveKit
import SwiftUI

/// The « Expliquer » popover: why the worktree exists, whether it can go.
struct ExplainView: View {
    let entry: WorktreeEntry
    let repo: RepoSnapshot
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(entry.worktree.title).font(.headline)
            switch model.explanation(for: entry) {
            case .running, nil:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Lecture de l'historique git, de la mémoire et des dernières sessions Claude Code…")
                        .font(.callout).foregroundStyle(.secondary)
                }
            case .done(let explanation):
                Text(markdown(explanation.text)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    Text(footer(explanation)).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Copier") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(explanation.text, forType: .string)
                    }
                    Button("Relancer") { model.explain(entry, in: repo, force: true) }
                }
                .buttonStyle(.borderless)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(
                    .callout)
                Button("Réessayer") { model.explain(entry, in: repo, force: true) }
            }
        }
        .padding(16)
        .frame(width: 460)
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    private func footer(_ explanation: Explanation) -> String {
        let cost = explanation.costUSD.map { String(format: "%.4f $", $0) } ?? "coût inconnu"
        return "\(explanation.model.rawValue.capitalized) · \(cost)"
    }
}
