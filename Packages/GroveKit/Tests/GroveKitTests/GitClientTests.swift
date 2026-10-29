import Foundation
import Testing

@testable import GroveKit

struct GitClientTests {
    private func statuses(_ fixture: GitFixture, repo: URL) async throws -> [String: WorktreeStatus] {
        let entries = try await fixture.client.worktreeStatuses(of: repo)
        return Dictionary(
            uniqueKeysWithValues: entries.map {
                (URL(fileURLWithPath: $0.worktree.path).lastPathComponent, $0.status)
            })
    }

    @Test func classifiesEveryWorktreeState() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")

        try fixture.addWorktree("wt-merged", branch: "merged", of: repo)
        let wip = try fixture.addWorktree("wt-wip", branch: "wip", of: repo)
        try "x".write(to: wip.appending(path: "new.txt"), atomically: true, encoding: .utf8)
        let unmerged = try fixture.addWorktree("wt-unmerged", branch: "feat", of: repo)
        try fixture.commit("work", in: unmerged)
        let detached = try fixture.addWorktree("wt-detached", of: repo)
        try fixture.commit("orphan", in: detached)
        try fixture.addWorktree("wt-detached-ok", of: repo)
        let locked = try fixture.addWorktree("wt-locked", branch: "locked", of: repo)
        try fixture.git("worktree", "lock", "--reason", "usb", locked.path, in: repo)
        let gone = try fixture.addWorktree("wt-gone", branch: "gone", of: repo)
        try FileManager.default.removeItem(at: gone)

        let result = try await statuses(fixture, repo: repo)

        #expect(result["app"] == .main)
        #expect(result["wt-merged"] == .merged)
        #expect(result["wt-wip"] == .wip(changes: ["?? new.txt"]))
        #expect(result["wt-unmerged"] == .unmerged)
        #expect(result["wt-detached"] == .detachedUnique)
        #expect(result["wt-detached-ok"] == .merged)
        #expect(result["wt-locked"] == .locked)
        #expect(result["wt-gone"] == .prunable)
    }

    @Test func detachedCommitKnownToAnotherBranchIsUnmergedNotUnique() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let detached = try fixture.addWorktree("wt-d", of: repo)
        try fixture.commit("c", in: detached)
        try fixture.git("branch", "keeper", "HEAD", in: detached)

        #expect(try await statuses(fixture, repo: repo)["wt-d"] == .unmerged)
    }

    @Test func noBaseBranchMeansNothingIsRemovable() async throws {
        let fixture = try GitFixture()
        let repo = fixture.root.appending(path: "bare-ish")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try fixture.git("init", "-q", "-b", "trunk", in: repo)
        try fixture.commit("i", in: repo)
        let directory = fixture.root.appending(path: "wt")
        try fixture.git("worktree", "add", "-q", "-b", "b", directory.path, in: repo)

        #expect(try await fixture.client.defaultBase(of: repo) == nil)
        #expect(try await statuses(fixture, repo: repo)["wt"] == .unmerged)
    }

    @Test func renamedFileCountsAsOneChange() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        try "a".write(to: repo.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try fixture.git("add", "a.txt", in: repo)
        try fixture.git("commit", "-q", "-m", "a", in: repo)
        try fixture.git("push", "-q", "origin", "main", in: repo)
        let wt = try fixture.addWorktree("wt", branch: "r", of: repo)
        try fixture.git("mv", "a.txt", "b.txt", in: wt)

        #expect(try await statuses(fixture, repo: repo)["wt"] == .wip(changes: ["R  b.txt"]))
    }

    @Test func commitMadeAfterListingIsNotMissed() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let wt = try fixture.addWorktree("wt", branch: "live", of: repo)
        let listed = try await fixture.client.worktrees(of: repo)
        try fixture.commit("after listing", in: wt)

        let stale = try #require(listed.first { !$0.isMain })
        #expect(try await fixture.client.status(of: stale, base: "origin/main") == .unmerged)
    }

    @Test func unreadableWorktreeDoesNotFailTheRepo() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let broken = try fixture.addWorktree("wt-broken", branch: "x", of: repo)
        try "not a gitdir".write(to: broken.appending(path: ".git"), atomically: true, encoding: .utf8)
        try fixture.addWorktree("wt-ok", branch: "ok", of: repo)

        let result = try await statuses(fixture, repo: repo)

        guard case .unreadable = result["wt-broken"] else {
            Issue.record("expected .unreadable, got \(String(describing: result["wt-broken"]))")
            return
        }
        #expect(result["wt-ok"] == .merged)
    }

    @Test func missingExecutableThrowsInsteadOfHanging() async throws {
        let fixture = try GitFixture()
        let client = GitClient(gitPath: "/nonexistent/git")
        await #expect(throws: (any Error).self) { try await client.worktrees(of: fixture.root) }
    }

    @Test func staleOriginHeadFallsBackToAnExistingBranch() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        try fixture.git("symbolic-ref", "refs/remotes/origin/HEAD", "refs/remotes/origin/master", in: repo)

        #expect(try await fixture.client.defaultBase(of: repo) == "origin/main")
    }

    @Test func defaultBaseFollowsOriginHead() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        #expect(try await fixture.client.defaultBase(of: repo) == "origin/main")
    }
}
