import Foundation

public struct WorktreeEntry: Equatable, Sendable, Identifiable {
    public let worktree: Worktree
    public let status: WorktreeStatus
    public var id: String { worktree.path }
}

/// Everything the UI needs about one repo that git can answer quickly (no sizes, no network).
public struct RepoSnapshot: Equatable, Sendable, Identifiable {
    public let url: URL
    public let name: String
    public let remote: RepoRemote?
    public let entries: [WorktreeEntry]
    /// Set when git could not even list the worktrees.
    public let error: String?
    /// Last commit, checkout or reset in the main working copy (mtime of `.git/logs/HEAD`).
    public let lastActivity: Date?
    public var id: String { url.path }
}

public enum RepoLoader {
    /// Loads every repo under `roots`, a few at a time (each repo costs several git processes).
    public static func load(
        roots: [URL], git: GitClient, concurrency: Int = 6, gitlabHosts: Set<String> = [],
        githubHosts: Set<String> = []
    ) async -> [RepoSnapshot] {
        let repos = RepoScanner().repositories(under: roots)
        var snapshots: [RepoSnapshot] = []
        await withTaskGroup(of: RepoSnapshot.self) { group in
            var iterator = repos.makeIterator()
            func addNext() {
                guard let repo = iterator.next() else { return }
                group.addTask {
                    await snapshot(of: repo, git: git, gitlabHosts: gitlabHosts, githubHosts: githubHosts)
                }
            }
            for _ in 0..<concurrency { addNext() }
            while let done = await group.next() {
                snapshots.append(done)
                addNext()
            }
        }
        return snapshots.sorted { $0.url.path < $1.url.path }
    }

    public static func snapshot(
        of repo: URL, git: GitClient, gitlabHosts: Set<String> = [], githubHosts: Set<String> = []
    ) async -> RepoSnapshot {
        let name = RepoName.displayName(for: repo)
        do {
            async let entries = git.worktreeStatuses(of: repo)
            async let remoteURL = git.remoteURL(of: repo)
            let remote = try await remoteURL.flatMap {
                RepoRemote(remoteURL: $0, gitlabHosts: gitlabHosts, githubHosts: githubHosts)
            }
            return RepoSnapshot(
                url: repo, name: name, remote: remote, entries: try await entries, error: nil,
                lastActivity: lastActivity(of: repo))
        } catch {
            return RepoSnapshot(
                url: repo, name: name, remote: nil, entries: [], error: String(describing: error),
                lastActivity: lastActivity(of: repo))
        }
    }

    private static func lastActivity(of repo: URL) -> Date? {
        let log = repo.appending(path: ".git/logs/HEAD").path
        return (try? FileManager.default.attributesOfItem(atPath: log))?[.modificationDate] as? Date
    }
}
