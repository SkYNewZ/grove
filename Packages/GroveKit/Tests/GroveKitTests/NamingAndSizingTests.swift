import Foundation
import Testing

@testable import GroveKit

struct NamingAndSizingTests {
    @Test(arguments: [
        ("# Demo App\n\nText", "Demo App"),
        ("---\ntitle: x\n---\n# After front matter", "After front matter"),
        ("<!-- # hidden -->\n# Real", "Real"),
        ("```sh\n# not a title\n```\n# Real", "Real"),
        ("<h1 align=\"center\">Centered <b>Name</b></h1>", "Centered Name"),
        (
            "[![CI](https://x/badge.svg)](https://x)\n# [Linked](https://y) **Bold** `code` #",
            "Linked Bold code"
        ),
        ("Setext Title\n=====\nbody", "Setext Title"),
    ])
    func extractsTitle(markdown: String, expected: String) {
        #expect(RepoName.readmeTitle(markdown) == expected)
    }

    @Test func noTitleMeansNoName() {
        #expect(RepoName.readmeTitle("just text\n\n## only h2") == nil)
    }

    @Test func readmeTitleWinsOverFolderName() throws {
        let fixture = try GitFixture()
        let repo = fixture.root.appending(path: "folder-name")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        #expect(RepoName.displayName(for: repo) == "folder-name")

        try "# Nice Name\n".write(to: repo.appending(path: "readme.md"), atomically: true, encoding: .utf8)
        #expect(RepoName.displayName(for: repo) == "Nice Name")
    }

    private func makeFiles(_ directory: URL, count: Int, kilobytes: Int) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for index in 0..<count {
            try Data(count: kilobytes * 1024).write(to: directory.appending(path: "f\(index).bin"))
        }
    }

    private func duKilobytes(_ directory: URL) throws -> Int64 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        process.arguments = ["-sk", directory.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return Int64(text.split(whereSeparator: \.isWhitespace).first ?? "") ?? -1
    }

    @Test func sizeMatchesDuWithinOnePercent() throws {
        let fixture = try GitFixture()
        let tree = fixture.root.appending(path: "tree")
        try makeFiles(tree, count: 30, kilobytes: 1000)
        try makeFiles(tree.appending(path: "sub/deeper"), count: 10, kilobytes: 500)

        let ours = Double(DiskUsage.allocatedSize(of: tree)) / 1024
        let du = Double(try duKilobytes(tree))

        #expect(abs(ours - du) / du < 0.01)
    }

    @Test func nestedWorktreesAreNotCountedTwice() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        try makeFiles(repo.appending(path: "data"), count: 5, kilobytes: 200)
        let nested = repo.appending(path: ".claude/worktrees/wt")
        try fixture.git("worktree", "add", "-q", "-b", "n", nested.path, "main", in: repo)
        try makeFiles(nested.appending(path: "data"), count: 20, kilobytes: 200)

        let worktrees = try await fixture.client.worktrees(of: repo)
        let sizes = await DiskUsage.measure(worktrees)

        let mainSize = try #require(
            sizes.perWorktree[repo.path]
                ?? sizes.perWorktree.first { PathIdentity.same($0.key, repo.path) }?.value)
        let nestedSize = try #require(
            sizes.perWorktree.first { PathIdentity.same($0.key, nested.path) }?.value)
        // Main would be at least as big as the nested worktree if it still included it.
        #expect(nestedSize > 20 * 200 * 1024 && mainSize < nestedSize)
        #expect(sizes.total == mainSize + nestedSize)
    }

    @Test func locatesGitEvenWithoutAShellPath() async {
        let tools = await ToolLocator.locate()
        #expect(tools.git != nil)
    }
}
