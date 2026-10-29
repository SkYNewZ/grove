import Foundation
import Testing

@testable import GroveKit

struct WatcherTests {
    @Test func reportsTheRepoWhenAWorktreeIsAdded() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let (events, continuation) = AsyncStream.makeStream(of: String.self)
        let watcher = GitDirectoryWatcher(repos: [repo], latency: 0.2) { continuation.yield($0.path) }
        defer { _ = watcher }
        try await Task.sleep(for: .milliseconds(500))

        try fixture.addWorktree("wt", branch: "w", of: repo)

        let first = try await withThrowingTaskGroup(of: String?.self) { group in
            group.addTask { await events.first { _ in true } }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
        #expect(first.map { PathIdentity.same($0, repo.path) } == true)
    }

    @Test func parsesLoggedInHosts() {
        let text = """
            gitlab.corp.example
              ✓ Logged in to gitlab.corp.example as me
            github.com
              ✓ Logged in to GitHub.com account x
            """
        #expect(ForgeHosts.parse(text) == ["gitlab.corp.example", "github.com"])
    }

    @Test func onlyWorktreeListChangesTriggerAReload() {
        #expect(GitDirectoryWatcher.isWorktreeListChange("/r/.git/worktrees"))
        #expect(GitDirectoryWatcher.isWorktreeListChange("/r/.git/worktrees/wt"))
        #expect(GitDirectoryWatcher.isWorktreeListChange("/r/.git/worktrees/wt/locked"))
        #expect(!GitDirectoryWatcher.isWorktreeListChange("/r/.git/worktrees/wt/HEAD"))
        #expect(!GitDirectoryWatcher.isWorktreeListChange("/r/.git/worktrees/wt/logs/HEAD"))
        #expect(!GitDirectoryWatcher.isWorktreeListChange("/r/.git/index"))
    }
}
