import Foundation
import Testing

@testable import GroveKit

/// The invariant under test: removing a worktree never loses a commit or a file.
struct SafeRemoverTests {
    private func remover(_ fixture: GitFixture) -> SafeRemover {
        let trashDirectory = fixture.root.appending(path: "trash")
        return SafeRemover(
            git: fixture.client,
            trash: { url in
                try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
                let destination = trashDirectory.appending(
                    path: "\(UUID().uuidString)-\(url.lastPathComponent)")
                try FileManager.default.moveItem(at: url, to: destination)
                return destination
            })
    }

    private func worktree(_ directory: URL, in repo: URL, _ fixture: GitFixture) async throws -> Worktree {
        let all = try await fixture.client.worktrees(of: repo)
        return try #require(all.first { $0.path.hasSuffix(directory.lastPathComponent) })
    }

    private func listedNames(_ fixture: GitFixture, repo: URL) async throws -> [String] {
        try await fixture.client.worktrees(of: repo).map { URL(fileURLWithPath: $0.path).lastPathComponent }
    }

    @Test func removesMergedWorktreeKeepingBackupRefAndFiles() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "done", of: repo)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        #expect(!plan.requiresStrongConfirmation)
        let result = try await sut.remove(plan, strongConfirmed: false)

        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try await listedNames(fixture, repo: repo) == ["app"])
        let trashed = try #require(result.trashedTo)
        #expect(FileManager.default.fileExists(atPath: trashed.appending(path: ".git").path))
        let backup = try #require(result.backupRefs.first)
        #expect(
            try fixture.git("rev-parse", backup, in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
                == plan.head)
        #expect(result.branchDeleted)
        #expect(try fixture.git("branch", "--list", "done", in: repo).isEmpty)
    }

    @Test func uncommittedWorkNeedsStrongConfirmationAndSurvivesInTrash() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "wip", of: repo)
        try "precious".write(to: directory.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        #expect(plan.dirtyFiles == ["?? notes.txt"] && plan.requiresStrongConfirmation)
        await #expect(throws: RemovalError.needsStrongConfirmation) {
            try await sut.remove(plan, strongConfirmed: false)
        }
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "notes.txt").path))

        let result = try await sut.remove(plan, strongConfirmed: true)
        let kept = try #require(result.trashedTo).appending(path: "notes.txt")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "precious")
    }

    @Test func refusesEverythingThatCouldLoseCommits() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let unmerged = try fixture.addWorktree("wt-unmerged", branch: "feat", of: repo)
        try fixture.commit("work", in: unmerged)
        let orphan = try fixture.addWorktree("wt-orphan", of: repo)
        try fixture.commit("orphan", in: orphan)
        let locked = try fixture.addWorktree("wt-locked", branch: "lk", of: repo)
        try fixture.git("worktree", "lock", locked.path, in: repo)
        let sut = remover(fixture)

        let all = try await fixture.client.worktrees(of: repo)
        let expectations: [(String, WorktreeStatus)] = [
            ("app", .main), ("wt-unmerged", .unmerged), ("wt-orphan", .detachedUnique),
            ("wt-locked", .locked),
        ]
        for (name, expected) in expectations {
            let target = try #require(all.first { $0.path.hasSuffix(name) })
            await #expect(throws: RemovalError.blocked(expected)) {
                try await sut.plan(for: target, in: repo)
            }
        }
        for directory in [unmerged, orphan, locked, repo] {
            #expect(FileManager.default.fileExists(atPath: directory.path))
        }
        #expect(try fixture.git("for-each-ref", "refs/grove-backup", in: repo).isEmpty)
    }

    @Test func commitsOnlyInTheReflogStayReachable() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "reset", of: repo)
        try fixture.commit("dropped", in: directory)
        let dropped = try fixture.git("rev-parse", "HEAD", in: directory).trimmingCharacters(
            in: .whitespacesAndNewlines)
        try fixture.git("reset", "-q", "--hard", "HEAD~1", in: directory)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        _ = try await sut.remove(plan, strongConfirmed: false)

        let holders = try fixture.git(
            "for-each-ref", "--contains", dropped, "--format=%(refname)", "refs/grove-backup", in: repo)
        #expect(!holders.isEmpty)
        try fixture.git("cat-file", "-e", dropped, in: repo)
    }

    @Test func prunableWorktreeIsBackedUpAndForgotten() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt-gone", branch: "gone", of: repo)
        let head = try fixture.git("rev-parse", "HEAD", in: directory).trimmingCharacters(
            in: .whitespacesAndNewlines)
        try FileManager.default.removeItem(at: directory)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        let result = try await sut.remove(plan, strongConfirmed: false)

        #expect(result.trashedTo == nil)
        let backup = try #require(result.backupRefs.first)
        #expect(
            try fixture.git("rev-parse", backup, in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
                == head)
        #expect(try await listedNames(fixture, repo: repo) == ["app"])
    }

    @Test func ignoredFilesAreListedAndKeptInTrash() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        try ".env\n".write(to: repo.appending(path: ".gitignore"), atomically: true, encoding: .utf8)
        try fixture.git("add", ".gitignore", in: repo)
        try fixture.git("commit", "-q", "-m", "ignore", in: repo)
        try fixture.git("push", "-q", "origin", "main", in: repo)
        let directory = try fixture.addWorktree("wt", branch: "env", of: repo)
        try "SECRET".write(to: directory.appending(path: ".env"), atomically: true, encoding: .utf8)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        #expect(plan.ignoredFiles == ["!! .env"])
        let result = try await sut.remove(plan, strongConfirmed: false)

        let kept = try #require(result.trashedTo).appending(path: ".env")
        #expect(try String(contentsOf: kept, encoding: .utf8) == "SECRET")
    }

    @Test func hiddenModificationsRequireStrongConfirmation() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        try "a".write(to: repo.appending(path: "a.txt"), atomically: true, encoding: .utf8)
        try fixture.git("add", "a.txt", in: repo)
        try fixture.git("commit", "-q", "-m", "a", in: repo)
        try fixture.git("push", "-q", "origin", "main", in: repo)
        let directory = try fixture.addWorktree("wt", branch: "hidden", of: repo)
        try fixture.git("update-index", "--assume-unchanged", "a.txt", in: directory)
        try "edited".write(to: directory.appending(path: "a.txt"), atomically: true, encoding: .utf8)

        let plan = try await remover(fixture).plan(for: worktree(directory, in: repo, fixture), in: repo)

        #expect(plan.dirtyFiles.isEmpty)
        #expect(plan.hiddenModifiedFiles == ["h a.txt"] && plan.requiresStrongConfirmation)
    }

    @Test func staleReviewIsRejected() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "late", of: repo)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        try "new".write(to: directory.appending(path: "late.txt"), atomically: true, encoding: .utf8)

        await #expect(throws: RemovalError.changedSinceReview) {
            try await sut.remove(plan, strongConfirmed: true)
        }
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "late.txt").path))
    }

    // MARK: - Findings of the final independent review

    @Test func refusesAWorktreeWithInitializedSubmodules() async throws {
        let fixture = try GitFixture()
        let library = try fixture.makeRepo("lib")
        let repo = try fixture.makeRepo("app")
        try fixture.git(
            "-c", "protocol.file.allow=always", "submodule", "add", "-q", library.path, "vendor/lib", in: repo
        )
        try fixture.git("commit", "-q", "-m", "add submodule", in: repo)
        try fixture.git("push", "-q", "origin", "main", in: repo)
        let directory = try fixture.addWorktree("wt", branch: "with-sub", of: repo)
        try fixture.git("-c", "protocol.file.allow=always", "submodule", "update", "--init", in: directory)
        let target = try await worktree(directory, in: repo, fixture)

        await #expect(throws: RemovalError.submodules(target.path)) {
            try await remover(fixture).plan(for: target, in: repo)
        }
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aNestedWorktreeWithUniqueCommitsBlocksTheOuterOne() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let outer = try fixture.addWorktree("outer", branch: "outer", of: repo)
        let inner = outer.appending(path: ".claude/worktrees/inner")
        try fixture.git("worktree", "add", "-q", "--detach", inner.path, "main", in: repo)
        try fixture.commit("only copy", in: inner)

        await #expect(throws: RemovalError.blocked(.detachedUnique)) {
            try await remover(fixture).plan(for: worktree(outer, in: repo, fixture), in: repo)
        }
        #expect(FileManager.default.fileExists(atPath: inner.path))
    }

    @Test func aRemovableNestedWorktreeIsListedAndBackedUp() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        // Like a real setup, `.claude/` is ignored, so the nested worktree is not an untracked change.
        try ".claude/\n".write(
            to: repo.appending(path: ".git/info/exclude"), atomically: true, encoding: .utf8)
        let outer = try fixture.addWorktree("outer", branch: "outer", of: repo)
        let inner = outer.appending(path: ".claude/worktrees/inner")
        try fixture.git("worktree", "add", "-q", "-b", "inner", inner.path, "main", in: repo)
        try fixture.commit("dropped", in: inner)
        let dropped = try fixture.git("rev-parse", "HEAD", in: inner).trimmingCharacters(
            in: .whitespacesAndNewlines)
        try fixture.git("reset", "-q", "--hard", "HEAD~1", in: inner)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(outer, in: repo, fixture), in: repo)
        #expect(plan.nested.count == 1)
        _ = try await sut.remove(plan, strongConfirmed: false)

        let holders = try fixture.git(
            "for-each-ref", "--contains", dropped, "--format=%(refname)", "refs/grove-backup", in: repo)
        #expect(!holders.isEmpty)
        #expect(try await listedNames(fixture, repo: repo) == ["app"])
    }

    @Test func reflogOnlyCommitsOfAMissingWorktreeAreKept() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", of: repo)
        try fixture.commit("lost", in: directory)
        let lost = try fixture.git("rev-parse", "HEAD", in: directory).trimmingCharacters(
            in: .whitespacesAndNewlines)
        try fixture.git("reset", "-q", "--hard", "HEAD~1", in: directory)
        try FileManager.default.removeItem(at: directory)
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        _ = try await sut.remove(plan, strongConfirmed: false)

        let holders = try fixture.git(
            "for-each-ref", "--contains", lost, "--format=%(refname)", "refs/grove-backup", in: repo)
        #expect(!holders.isEmpty)
    }

    @Test func oldReflogCommitsSurviveALongReflog() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        for index in 1...60 { try fixture.commit("main \(index)", in: repo) }
        try fixture.git("push", "-q", "origin", "main", in: repo)
        let directory = try fixture.addWorktree("wt", branch: "long", of: repo)
        try fixture.commit("old work", in: directory)
        let old = try fixture.git("rev-parse", "HEAD", in: directory).trimmingCharacters(
            in: .whitespacesAndNewlines)
        try fixture.git("reset", "-q", "--hard", "main~1", in: directory)
        for index in 2...60 { try fixture.git("reset", "-q", "--hard", "main~\(index)", in: directory) }
        let sut = remover(fixture)

        let plan = try await sut.plan(for: worktree(directory, in: repo, fixture), in: repo)
        _ = try await sut.remove(plan, strongConfirmed: false)

        let holders = try fixture.git(
            "for-each-ref", "--contains", old, "--format=%(refname)", "refs/grove-backup", in: repo)
        #expect(!holders.isEmpty)
    }
}
