import Foundation
import Testing

@testable import GroveKit

struct WorktreeOriginTests {
    @Test func codexDisplayNameIsTheWorktreeIdNotTheRepoName() {
        let codex = Worktree(
            path: NSHomeDirectory() + "/.codex/worktrees/ci-stack-validation/demo-app")
        #expect(codex.displayName == "ci-stack-validation")
        #expect(Worktree(path: NSHomeDirectory() + "/.codex/worktrees/abcd").displayName == "abcd")
        #expect(Worktree(path: "/Users/q/src/app/.claude/worktrees/fix-x").displayName == "fix-x")
    }

    @Test(arguments: [
        ("/Users/q/src/demo-app/.claude/worktrees/foo", WorktreeOrigin.claudeCode),
        ("/Users/q/.claude/worktrees/foo", .claudeCode),
        ("/Users/q/.codex/worktrees/ci-stack-validation/x", .codex),
    ])
    func recognisesWorktreesMadeByAgents(path: String, origin: WorktreeOrigin) {
        #expect(WorktreeOrigin.detect(path: path, home: "/Users/q") == origin)
        #expect(Worktree(path: path).origin == WorktreeOrigin.detect(path: path))
    }

    @Test(arguments: [
        "/Users/q/src/demo-app-deps",
        "/Users/q/src/x/.claude-worktrees/y",
        "/Users/q/src/x/.claude/worktrees",
        "/Users/other/.codex/worktrees/a",
        "/Users/qq/.codex/worktrees/a",
    ])
    func leavesHandMadeWorktreesWithoutOrigin(path: String) {
        #expect(WorktreeOrigin.detect(path: path, home: "/Users/q") == nil)
    }

    @Test func toleratesATrailingSlashOnHome() {
        #expect(
            WorktreeOrigin.detect(path: "/Users/q/.codex/worktrees/a/b", home: "/Users/q/") == .codex)
    }
}
