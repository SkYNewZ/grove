import GroveKit
import SwiftUI

extension WorktreeStatus {
    var tint: Color {
        switch self {
        case .merged: .green
        case .wip, .prunable: .orange
        case .detachedUnique, .unreadable: .red
        case .main, .locked, .unmerged: .secondary
        }
    }
}

extension Worktree {
    /// Branch name, or the short commit when detached.
    var title: String {
        if let branch { return branch }
        return "HEAD détaché" + (head.map { " · \($0.prefix(7))" } ?? "")
    }

}

func formattedSize(_ bytes: Int64?) -> String {
    bytes.map { $0.formatted(.byteCount(style: .file)) } ?? "…"
}

/// "#7" (GitHub) or "!7" (GitLab) from `…/pull/7` or `…/merge_requests/7`.
func requestNumber(_ url: URL, on forge: Forge) -> String? {
    guard url.lastPathComponent.allSatisfy(\.isNumber) else { return nil }
    return (forge == .github ? "#" : "!") + url.lastPathComponent
}

extension RepoSnapshot {
    var worktreeCountLabel: String { "\(entries.count) worktree\(entries.count > 1 ? "s" : "")" }
}
