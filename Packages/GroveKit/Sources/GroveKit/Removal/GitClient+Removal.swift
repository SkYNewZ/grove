import Foundation

/// Git operations only the remover needs. All of them are read-only except the last four.
extension GitClient {
    func fetch(_ repo: URL) async throws {
        _ = try await git(["fetch", "--quiet", "--prune", "origin"], in: repo, timeout: .seconds(30))
    }

    func headCommit(in directory: URL) async throws -> String {
        try await git(["rev-parse", "HEAD"], in: directory).stdoutString.trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    /// Paths git ignores (`.env`, build output), as `!! path`. Not part of `WorktreeStatus.merged`.
    func ignoredEntries(in directory: URL) async throws -> [String] {
        let out = try await git(["status", "--porcelain", "-z", "--ignored=matching"], in: directory)
        return Self.fields(out.stdout).filter { $0.hasPrefix("!! ") }
    }

    /// Tracked files whose changes git is told to ignore (`assume-unchanged`, lowercase tag; `skip-worktree`, `S`).
    /// shortcut: a sparse checkout lists every out-of-cone file here, which only makes the confirmation louder.
    func hiddenModifiedEntries(in directory: URL) async throws -> [String] {
        let out = try await git(["ls-files", "-v", "-z"], in: directory)
        return Self.fields(out.stdout).filter { entry in
            guard let tag = entry.first else { return false }
            return tag.isLowercase || tag == "S"
        }
    }

    /// Commits this ref's reflog still points to, newest first (empty when the ref has no reflog).
    func reflogCommits(of ref: String, in directory: URL) async throws -> [String] {
        let out = try await run(
            ["reflog", "show", "--format=%H", ref], in: directory, accepting: [0, 128])
        return out.status == 0 ? out.stdoutString.split(separator: "\n").map(String.init) : []
    }

    /// The subset of `commits` that no branch, remote branch or tag contains, in one git call.
    func commitsOnNoRef(_ commits: [String], in repo: URL) async throws -> [String] {
        guard !commits.isEmpty else { return [] }
        // `--stdin` must come before `--not` so the listed commits are the positive side.
        let out = try await run(
            ["rev-list", "--stdin", "--ignore-missing", "--not", "--branches", "--remotes", "--tags"],
            in: repo, accepting: [0], input: Data((commits.joined(separator: "\n") + "\n").utf8))
        let found = Set(out.stdoutString.split(separator: "\n").map(String.init))
        return commits.filter(found.contains)
    }

    /// `<git-common-dir>/worktrees/<id>`: where git keeps this worktree's HEAD, reflog and submodule repos.
    /// Matched through the `gitdir` file inside, since git suffixes ids when names collide.
    func adminDirectory(for worktreePath: String, in repo: URL) async throws -> URL? {
        let common = try await git(["rev-parse", "--path-format=absolute", "--git-common-dir"], in: repo)
            .stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = URL(fileURLWithPath: common).appending(path: "worktrees")
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for id in ids {
            let folder = root.appending(path: id)
            guard let text = try? String(contentsOf: folder.appending(path: "gitdir"), encoding: .utf8) else {
                continue
            }
            let dotGit = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if PathIdentity.same(URL(fileURLWithPath: dotGit).deletingLastPathComponent().path, worktreePath)
            {
                return folder
            }
        }
        return nil
    }

    /// Creates `ref` → `commit`, failing if `ref` already exists. Returns false when it did.
    func createRef(_ ref: String, at commit: String, in repo: URL) async throws -> Bool {
        let zero = String(repeating: "0", count: 40)
        let out = try await run(["update-ref", ref, commit, zero], in: repo, accepting: [0, 128])
        return out.status == 0
    }

    /// `git worktree prune`: removes bookkeeping of every worktree whose directory is gone.
    func pruneWorktrees(in repo: URL) async throws {
        _ = try await git(["worktree", "prune"], in: repo)
    }

    /// `git branch -d` (never `-D`). Returns git's refusal message instead of throwing.
    func deleteBranch(_ branch: String, in repo: URL) async throws -> String? {
        let out = try await run(["branch", "-d", branch], in: repo, accepting: [0, 1])
        return out.status == 0 ? nil : out.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func fields(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }
}
