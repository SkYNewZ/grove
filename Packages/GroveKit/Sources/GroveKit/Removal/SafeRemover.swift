import Foundation

/// What removing one worktree would do, computed from fresh git state. Show it, then pass it to `remove`.
public struct RemovalPlan: Equatable, Sendable {
    public let repo: URL
    public let worktree: Worktree
    /// Live HEAD (the recorded one when the directory is already gone).
    public let head: String?
    public let dirtyFiles: [String]
    public let ignoredFiles: [String]
    public let hiddenModifiedFiles: [String]
    public let runningProcesses: [String]
    /// Worktrees living inside the target's folder (`.claude/worktrees/*`): they leave with it, so each gets
    /// its own backup, and any of them that is not removable blocks the whole removal.
    public let nested: [NestedWorktree]
    /// Other worktrees whose directory is gone: `git worktree prune` drops them too, so they get a backup.
    public let collateralPruned: [Worktree]
    /// Set when `git fetch` failed: the merged check then ran against a possibly stale base (safe side).
    public let fetchWarning: String?

    public var requiresStrongConfirmation: Bool {
        !dirtyFiles.isEmpty || !hiddenModifiedFiles.isEmpty || !runningProcesses.isEmpty
    }
}

public struct NestedWorktree: Equatable, Sendable {
    public let worktree: Worktree
    public let head: String?
}

public struct RemovalResult: Equatable, Sendable {
    /// Refs under `refs/grove-backup/` that keep every removed commit reachable.
    public let backupRefs: [String]
    /// Where the directory went (Trash), nil when it was already gone.
    public let trashedTo: URL?
    public let branchDeleted: Bool
    /// The worktree's branch, when it had one.
    public let branch: String?
    /// git's reason when the branch was kept.
    public let branchNote: String?
    /// Other missing-folder worktrees that `git worktree prune` forgot in the same run (each was backed up).
    public let alsoPruned: [String]
}

public enum RemovalError: Error, Equatable, LocalizedError {
    case notFound
    case blocked(WorktreeStatus)
    case needsStrongConfirmation
    case changedSinceReview
    case backupFailed(String)
    case trashFailed(String)
    case submodules(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: "Ce worktree n'existe plus."
        case .blocked(let status):
            "Suppression refusée : \(Self.blockReason(for: status) ?? "état inattendu.")"
        case .needsStrongConfirmation:
            "Ce worktree contient du travail non commité : confirmation forte requise."
        case .changedSinceReview: "Le worktree a changé depuis l'aperçu. Relis l'aperçu avant de supprimer."
        case .backupFailed(let detail): "Sauvegarde des commits impossible, rien n'a été supprimé. \(detail)"
        case .trashFailed(let detail): "Déplacement dans la Corbeille impossible. \(detail)"
        case .submodules(let path):
            "Suppression refusée : « \(URL(fileURLWithPath: path).lastPathComponent) » contient des sous-modules initialisés dont git effacerait les dépôts."
        }
    }

    /// Why a worktree in this status cannot be removed, nil when it can (`merged`, `wip`, `prunable`).
    public static func blockReason(for status: WorktreeStatus) -> String? {
        switch status {
        case .main: "c'est le dépôt principal."
        case .locked: "il est verrouillé."
        case .unmerged:
            "ses commits ne sont pas dans la branche principale (ou la branche a été fusionnée en squash)."
        case .detachedUnique: "HEAD détaché : ses commits ne sont dans aucune branche."
        case .unreadable(let detail): "git ne peut pas le lire (\(detail))."
        case .merged, .wip, .prunable: nil
        }
    }
}

/// The only way Grove removes a worktree. Order matters: fetch → fresh status → backup refs → Trash → prune →
/// `branch -d`. Nothing is ever `rm`-ed, and a backup ref exists before anything moves.
public struct SafeRemover: Sendable {
    public typealias Trash = @Sendable (URL) throws -> URL?

    private let git: GitClient
    private let probe: ProcessProbe
    private let trash: Trash

    public init(
        git: GitClient = GitClient(), probe: ProcessProbe = ProcessProbe(),
        trash: @escaping Trash = SafeRemover.systemTrash
    ) {
        self.git = git
        self.probe = probe
        self.trash = trash
    }

    public static let systemTrash: Trash = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return result as URL?
    }

    /// Fetches (best effort), recomputes the status and gathers what the user must see before confirming.
    public func plan(for worktree: Worktree, in repo: URL) async throws -> RemovalPlan {
        try await makePlan(for: worktree, in: repo, fetch: true)
    }

    /// `reviewed` must still match reality; strong confirmation is enforced here, not only in the UI.
    public func remove(_ reviewed: RemovalPlan, strongConfirmed: Bool) async throws -> RemovalResult {
        let fresh = try await makePlan(for: reviewed.worktree, in: reviewed.repo, fetch: false)
        guard fresh.head == reviewed.head, fresh.dirtyFiles == reviewed.dirtyFiles,
            fresh.hiddenModifiedFiles == reviewed.hiddenModifiedFiles, fresh.nested == reviewed.nested
        else { throw RemovalError.changedSinceReview }
        if fresh.requiresStrongConfirmation && !strongConfirmed { throw RemovalError.needsStrongConfirmation }

        let repo = fresh.repo
        let stamp = Self.stamp()
        var refs: [String] = []
        do {
            refs += try await backup(fresh.worktree, head: fresh.head, repo: repo, stamp: stamp)
            for inner in fresh.nested {
                refs += try await backup(inner.worktree, head: inner.head, repo: repo, stamp: stamp)
            }
            for other in fresh.collateralPruned {
                refs += try await backup(other, head: other.head, repo: repo, stamp: stamp)
            }
        } catch {
            throw RemovalError.backupFailed(String(describing: error))
        }

        var trashed: URL?
        let directory = URL(fileURLWithPath: fresh.worktree.path)
        if FileManager.default.fileExists(atPath: directory.path) {
            do { trashed = try trash(directory) } catch {
                throw RemovalError.trashFailed(error.localizedDescription)
            }
        }
        try await git.pruneWorktrees(in: repo)

        var note: String?
        var deleted = false
        if let branch = fresh.worktree.branch {
            note = try await git.deleteBranch(branch, in: repo)
            deleted = note == nil
        }
        return RemovalResult(
            backupRefs: refs, trashedTo: trashed, branchDeleted: deleted, branch: fresh.worktree.branch,
            branchNote: note,
            alsoPruned: fresh.collateralPruned.map(\.directoryName))
    }

    // MARK: - Planning

    private struct Assessment {
        let dirty: [String]
        let head: String?
        let isPrunable: Bool
    }

    /// Refuses anything that could lose work; otherwise says what is uncommitted and where HEAD is.
    private func assess(_ worktree: Worktree, base: String?, repo: URL) async throws -> Assessment {
        let status: WorktreeStatus
        do {
            status = try await git.status(of: worktree, base: base)
        } catch let error as GitError {
            throw RemovalError.blocked(.unreadable(error.stderr))
        }
        var dirty: [String] = []
        switch status {
        case .merged, .prunable: break
        case .wip(let changes): dirty = changes
        default: throw RemovalError.blocked(status)
        }
        // `worktree prune` erases the admin folder, and with it the repositories of initialized submodules.
        if let admin = try await git.adminDirectory(for: worktree.path, in: repo),
            let modules = try? FileManager.default.contentsOfDirectory(
                atPath: admin.appending(path: "modules").path),
            !modules.isEmpty
        {
            throw RemovalError.submodules(worktree.path)
        }
        let head =
            status == .prunable
            ? worktree.head : try await git.headCommit(in: URL(fileURLWithPath: worktree.path))
        return Assessment(dirty: dirty, head: head, isPrunable: status == .prunable)
    }

    private func makePlan(for worktree: Worktree, in repo: URL, fetch: Bool) async throws -> RemovalPlan {
        var warning: String?
        if fetch {
            do { try await git.fetch(repo) } catch { warning = String(describing: error) }
        }
        let all = try await git.worktrees(of: repo)
        guard let target = all.first(where: { PathIdentity.same($0.path, worktree.path) }) else {
            throw RemovalError.notFound
        }
        let base = try await git.defaultBase(of: repo)
        let main = try await assess(target, base: base, repo: repo)

        var dirty = main.dirty
        var nested: [NestedWorktree] = []
        for inner in all
        where !PathIdentity.same(inner.path, target.path)
            && PathIdentity.isInside(inner.path, directory: target.path)
        {
            let result = try await assess(inner, base: base, repo: repo)
            nested.append(NestedWorktree(worktree: inner, head: result.head))
            dirty += result.dirty.map { "\(URL(fileURLWithPath: inner.path).lastPathComponent): \($0)" }
        }

        var ignored: [String] = []
        var hidden: [String] = []
        var processes: [String] = []
        if !main.isPrunable {
            let directory = URL(fileURLWithPath: target.path)
            ignored = try await git.ignoredEntries(in: directory)
            hidden = try await git.hiddenModifiedEntries(in: directory)
            processes = await probe.processes(withCwdUnder: target.path)
        }
        let collateral = all.filter { other in
            !PathIdentity.same(other.path, target.path) && !other.isMain && !other.isLocked
                && !PathIdentity.isInside(other.path, directory: target.path)
                && (other.prunableReason != nil || !FileManager.default.fileExists(atPath: other.path))
        }
        return RemovalPlan(
            repo: repo, worktree: target, head: main.head, dirtyFiles: dirty, ignoredFiles: ignored,
            hiddenModifiedFiles: hidden, runningProcesses: processes, nested: nested,
            collateralPruned: collateral, fetchWarning: warning)
    }

    // MARK: - Backup

    /// Pins the HEAD plus every commit only the reflogs still know (the worktree's own HEAD reflog, kept in
    /// the repo's admin folder, and its branch's), so nothing becomes garbage once prune and `branch -d` ran.
    private func backup(_ worktree: Worktree, head: String?, repo: URL, stamp: String) async throws
        -> [String]
    {
        let name = Self.refSafe(worktree.directoryName)
        guard let head else { return [] }
        var refs = [try await pin(head, as: "\(name)-\(stamp)", repo: repo)]

        var candidates: [String] = []
        if let admin = try await git.adminDirectory(for: worktree.path, in: repo) {
            candidates += try await git.reflogCommits(
                of: "worktrees/\(admin.lastPathComponent)/HEAD", in: repo)
        }
        if let branch = worktree.branch {
            candidates += try await git.reflogCommits(of: "refs/heads/\(branch)", in: repo)
        }
        var seen: Set<String> = [head]
        let unique = candidates.filter { seen.insert($0).inserted }
        for commit in try await git.commitsOnNoRef(unique, in: repo) {
            refs.append(try await pin(commit, as: "\(name)-\(stamp)-r\(refs.count)", repo: repo))
        }
        return refs
    }

    private func pin(_ commit: String, as leaf: String, repo: URL) async throws -> String {
        for attempt in 0..<10 {
            let ref = "refs/grove-backup/\(leaf)\(attempt == 0 ? "" : "-\(attempt)")"
            if try await git.createRef(ref, at: commit, in: repo) { return ref }
        }
        throw RemovalError.backupFailed("impossible de créer une référence de sauvegarde pour \(commit)")
    }

    // MARK: - Helpers

    private static func refSafe(_ name: String) -> String {
        let mapped = name.map { $0.isLetter || $0.isNumber || "._-".contains($0) ? $0 : "-" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
