import Foundation

public struct GitError: Error, Equatable, Sendable {
    public let arguments: [String]
    public let status: Int32
    public let stderr: String
}

public struct GitClient: Sendable {
    private let runner: ProcessRunner
    private let gitPath: String

    /// `environment` is for tests (isolated git config); production passes nothing.
    public init(gitPath: String = "/usr/bin/git", environment: [String: String] = [:]) {
        self.gitPath = gitPath
        // Optional locks off: a scan must never contend with the user's own git commands.
        runner = ProcessRunner(
            environment: environment.merging(["GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"]) { $1 })
    }

    public func worktrees(of repo: URL) async throws -> [Worktree] {
        let out = try await git(["worktree", "list", "--porcelain", "-z"], in: repo)
        return WorktreeListParser.parse(out.stdout)
    }

    /// Every worktree of `repo` with its removal status. A worktree git cannot read becomes `.unreadable`
    /// (never removable) instead of failing the whole repo.
    public func worktreeStatuses(of repo: URL) async throws -> [WorktreeEntry] {
        let base = try await defaultBase(of: repo)
        var result: [WorktreeEntry] = []
        for worktree in try await worktrees(of: repo) {
            do {
                let status = try await status(of: worktree, base: base)
                result.append(WorktreeEntry(worktree: worktree, status: status))
            } catch let error as GitError {
                result.append(WorktreeEntry(worktree: worktree, status: .unreadable(error.stderr)))
            }
        }
        return result
    }

    /// `origin/HEAD` if set, else the first of `origin/main`, `origin/master`, `main`, `master` that exists.
    public func defaultBase(of repo: URL) async throws -> String? {
        let head = try await run(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: repo, accepting: [0, 1])
        // origin/HEAD can point at a ref that no longer exists (default branch renamed): then fall through.
        if head.status == 0 {
            let name = head.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
            if try await resolves(name, in: repo) { return name }
        }
        for candidate in ["origin/main", "origin/master", "main", "master"] {
            if try await resolves(candidate, in: repo) { return candidate }
        }
        return nil
    }

    private func resolves(_ ref: String, in repo: URL) async throws -> Bool {
        try await run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"], in: repo, accepting: [0, 1])
            .status
            == 0
    }

    func status(of worktree: Worktree, base: String?) async throws -> WorktreeStatus {
        if worktree.isMain { return .main }
        if worktree.isLocked { return .locked }
        guard worktree.prunableReason == nil, FileManager.default.fileExists(atPath: worktree.path) else {
            return .prunable
        }
        guard !worktree.isBare else { return .unmerged }

        // HEAD is read live (not the SHA from the list) so a commit made since the listing is never missed.
        let directory = URL(fileURLWithPath: worktree.path)
        var merged = false
        if let base {
            let probe = try await run(
                ["merge-base", "--is-ancestor", "HEAD", base], in: directory, accepting: [0, 1])
            merged = probe.status == 0
        }
        guard merged else {
            if worktree.isDetached, try await !isReachableFromAnyRef(in: directory) { return .detachedUnique }
            return .unmerged
        }
        let changes = try await dirtyEntries(in: directory)
        return changes.isEmpty ? .merged : .wip(changes: changes)
    }

    /// True when a branch, remote branch or tag contains `commit` (the backup namespace does not count).
    func isReachableFromAnyRef(_ commit: String = "HEAD", in directory: URL) async throws -> Bool {
        let out = try await git(
            [
                "for-each-ref", "--contains", commit, "--format=%(refname)", "refs/heads", "refs/remotes",
                "refs/tags",
            ],
            in: directory)
        return !out.stdoutString.isEmpty
    }

    /// Changed paths (tracked and untracked) from `status --porcelain -z`.
    private func dirtyEntries(in directory: URL) async throws -> [String] {
        let out = try await git(["status", "--porcelain", "-z", "--untracked-files=all"], in: directory)
        var entries: [String] = []
        var fields = out.stdout.split(separator: 0, omittingEmptySubsequences: true).makeIterator()
        while let field = fields.next() {
            let entry = String(decoding: field, as: UTF8.self)
            entries.append(entry)
            // Renames and copies carry the original path as an extra field.
            if let first = entry.first, first == "R" || first == "C" { _ = fields.next() }
        }
        return entries
    }

    func git(_ arguments: [String], in directory: URL, timeout: Duration = .seconds(60)) async throws
        -> ProcessOutput
    {
        try await run(arguments, in: directory, accepting: [0], timeout: timeout)
    }

    /// Runs git; any exit status outside `accepting` throws a `GitError` carrying the real arguments.
    /// A git that outlives `timeout` (slow fsmonitor hook, dead remote) is killed and throws `ProcessTimeout`.
    func run(
        _ arguments: [String], in directory: URL, accepting: Set<Int32>, input: Data? = nil,
        timeout: Duration = .seconds(60)
    ) async throws -> ProcessOutput {
        let out = try await runner.run(gitPath, arguments, cwd: directory, input: input, timeout: timeout)
        guard accepting.contains(out.status) else {
            throw GitError(arguments: arguments, status: out.status, stderr: out.stderr)
        }
        return out
    }
}
