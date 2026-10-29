/// Why a worktree can or cannot be removed. Anything uncertain lands on the safe side (not removable).
public enum WorktreeStatus: Equatable, Sendable {
    /// The repo's own working copy: never removable.
    case main
    /// Directory missing: only the git bookkeeping is left.
    case prunable
    case locked
    /// HEAD is contained in the base branch and `git status` is clean. Ignored files (`.env`...) and
    /// assume-unchanged edits are not seen here: the remover must list them before confirming.
    case merged
    /// HEAD is merged but the tree has uncommitted changes (porcelain entries).
    case wip(changes: [String])
    /// HEAD is not in the base branch. Also what a squash-merged branch looks like.
    case unmerged
    /// Detached HEAD that no branch, remote branch or tag contains: removal would orphan its commits.
    case detachedUnique
    /// git failed on this worktree (corrupt, unborn HEAD...): the message is git's stderr.
    case unreadable(String)

    /// Short French name, shown in the UI and given to the explain prompt.
    public var label: String {
        switch self {
        case .main: "Principal"
        case .prunable: "Dossier manquant"
        case .locked: "Verrouillé"
        case .merged: "Mergé"
        case .wip: "Modifs locales"
        case .unmerged: "Non mergé"
        case .detachedUnique: "Commits orphelins"
        case .unreadable: "Illisible"
        }
    }
}
