import Foundation
import Testing

@testable import GroveKit

struct RepoScannerTests {
    @Test func findsMainReposOnlyAndSkipsWorktreesAndNoise() throws {
        let fixture = try GitFixture()
        let projects = fixture.root.appending(path: "src")
        let nested = projects.appending(path: "group")
        let top = try fixture.makeRepo("top", in: projects)
        let inGroup = try fixture.makeRepo("deep", in: nested)
        try fixture.addWorktree("linked", branch: "b", of: top)
        // Worktree placed under the scanned root: its `.git` is a file, so it must not count as a repo.
        let underRoot = projects.appending(path: "linked-in-root")
        try fixture.git("worktree", "add", "-q", "-b", "c", underRoot.path, "main", in: top)
        // A repo inside node_modules is noise.
        let noise = projects.appending(path: "node_modules/pkg")
        try FileManager.default.createDirectory(at: noise, withIntermediateDirectories: true)
        try fixture.git("init", "-q", in: noise)

        let found = RepoScanner().repositories(under: [projects])

        #expect(found.map(\.lastPathComponent).sorted() == ["deep", "top"])
        #expect(Set(found.map { $0.resolvingSymlinksInPath().path }) == [top.path, inGroup.path])
    }

    @Test func overlappingRootsListEachRepoOnce() throws {
        let fixture = try GitFixture()
        let group = fixture.root.appending(path: "group")
        _ = try fixture.makeRepo("r", in: group)

        #expect(RepoScanner().repositories(under: [fixture.root, group]).count == 1)
    }

    @Test func aRepoMayBeNamedLikeANoiseFolder() throws {
        let fixture = try GitFixture()
        _ = try fixture.makeRepo("vendor")
        _ = try fixture.makeRepo("target")

        let found = RepoScanner().repositories(under: [fixture.root])

        #expect(found.map(\.lastPathComponent).sorted() == ["target", "vendor"])
    }

    @Test func respectsMaxDepth() throws {
        let fixture = try GitFixture()
        let deep = fixture.root.appending(path: "a/b/c")
        _ = try fixture.makeRepo("r", in: deep)

        #expect(RepoScanner(maxDepth: 2).repositories(under: [fixture.root]).isEmpty)
        #expect(RepoScanner(maxDepth: 4).repositories(under: [fixture.root]).count == 1)
    }
}
