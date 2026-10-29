import Foundation
import Testing

@testable import GroveKit

struct WorktreeListParserTests {
    @Test func parsesEveryRecordKind() {
        let records = [
            "worktree /r\0HEAD aaa\0branch refs/heads/main\0\0",
            "worktree /r/with space\nnewline\0HEAD bbb\0detached\0\0",
            "worktree /w/locked\0HEAD ccc\0branch refs/heads/feat/x\0locked no reason given\0\0",
            "worktree /w/gone\0HEAD ddd\0detached\0locked\0prunable gitdir file points to non-existent location\0\0",
        ]
        let parsed = WorktreeListParser.parse(Data(records.joined().utf8))

        #expect(parsed.map(\.path) == ["/r", "/r/with space\nnewline", "/w/locked", "/w/gone"])
        #expect(parsed[0].branch == "main" && parsed[0].isMain)
        #expect(!parsed[1].isMain)
        #expect(parsed[1].isDetached && parsed[1].branch == nil)
        #expect(parsed[2].branch == "feat/x" && parsed[2].lockReason == "no reason given")
        #expect(parsed[3].lockReason == "" && parsed[3].isLocked)
        #expect(parsed[3].prunableReason?.hasPrefix("gitdir") == true)
    }

    @Test func emptyInputGivesNoWorktrees() {
        #expect(WorktreeListParser.parse(Data()).isEmpty)
    }
}
