import Foundation
import Testing

@testable import GroveKit

struct HostingTests {
    @Test(arguments: [
        ("git@github.com:example/demo-app.git", "github.com", "example/demo-app", Forge.github),
        ("https://github.com/example/demo-app", "github.com", "example/demo-app", Forge.github),
        ("https://user:tok@gitlab.com/g/sub/repo.git", "gitlab.com", "g/sub/repo", Forge.gitlab),
        ("ssh://git@gitlab.corp.example:2222/team/app.git", "gitlab.corp.example", "team/app", Forge.gitlab),
        ("git@git.corp.example:team/app.git", "git.corp.example", "team/app", Forge.gitlab),
    ])
    func parsesRemoteForms(url: String, host: String, path: String, forge: Forge) throws {
        let remote = try #require(RepoRemote(remoteURL: url, gitlabHosts: ["git.corp.example"]))
        #expect(remote.host == host && remote.path == path && remote.forge == forge)
        #expect(remote.webURL?.absoluteString == "https://\(host)/\(path)")
    }

    @Test func unknownHostHasNoForgeAndGarbageHasNoRemote() {
        #expect(RepoRemote(remoteURL: "git@bitbucket.org:a/b.git")?.forge == nil)
        #expect(RepoRemote(remoteURL: "/local/path/repo") == nil)
        #expect(RepoRemote(remoteURL: "") == nil)
    }

    @Test func readsOriginOrFirstRemote() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        #expect(try await fixture.client.remoteURL(of: repo)?.hasSuffix("app-origin.git") == true)

        try fixture.git("remote", "remove", "origin", in: repo)
        #expect(try await fixture.client.remoteURL(of: repo) == nil)
        try fixture.git("remote", "add", "upstream", "git@github.com:a/b.git", in: repo)
        #expect(try await fixture.client.remoteURL(of: repo) == "git@github.com:a/b.git")
    }

    @Test func parsesEveryStateFromGitHub() throws {
        let github = Data(
            #"""
            [{"headRefName":"feat/x","headRefOid":"aaa","url":"https://github.com/a/b/pull/7","state":"OPEN","title":"Add x","isCrossRepository":false},
             {"headRefName":"feat/old","headRefOid":"bbb","url":"https://github.com/a/b/pull/5","state":"MERGED","title":"Old"},
             {"headRefName":"feat/dead","url":"https://github.com/a/b/pull/4","state":"CLOSED"},
             {"headRefName":"feat/odd","url":"https://github.com/a/b/pull/3","state":"DRAFT"}]
            """#.utf8)

        let requests = PullRequestResolver.parseGitHub(github)

        #expect(requests.map(\.state) == [.open, .merged, .closed])
        #expect(requests.map(\.branch) == ["feat/x", "feat/old", "feat/dead"])
        #expect(requests.map(\.headSHA) == ["aaa", "bbb", nil])
        #expect(requests[0].title == "Add x" && requests[0].number == 7)
        #expect(PullRequestResolver.parseGitHub(Data("not json".utf8)).isEmpty)
    }

    @Test func parsesEveryStateFromGitLab() {
        let gitlab = Data(
            #"""
            [{"source_branch":"fix/y","sha":"ccc","web_url":"https://gl.example/g/r/-/merge_requests/3","state":"opened","title":"Fix y","source_project_id":3,"target_project_id":3},
             {"source_branch":"fix/z","sha":"ddd","web_url":"https://gl.example/g/r/-/merge_requests/2","state":"merged","source_project_id":3,"target_project_id":3},
             {"source_branch":"fix/w","web_url":"https://gl.example/g/r/-/merge_requests/1","state":"closed","source_project_id":3,"target_project_id":3},
             {"x":1}]
            """#.utf8)

        let requests = PullRequestResolver.parseGitLab(gitlab)

        #expect(requests.map(\.state) == [.open, .merged, .closed])
        #expect(requests.map(\.headSHA) == ["ccc", "ddd", nil])
        #expect(requests[0].title == "Fix y" && requests[0].number == 3)
    }

    @Test func ignoresRequestsComingFromForks() {
        let github = Data(
            #"[{"headRefName":"main","url":"https://github.com/a/b/pull/1","state":"OPEN","isCrossRepository":true},{"headRefName":"feat","url":"https://github.com/a/b/pull/2","state":"OPEN","isCrossRepository":false}]"#
                .utf8)
        let gitlab = Data(
            #"[{"source_branch":"main","web_url":"https://g/m/1","state":"merged","source_project_id":9,"target_project_id":3},{"source_branch":"feat","web_url":"https://g/m/2","state":"merged","source_project_id":3,"target_project_id":3}]"#
                .utf8)

        #expect(PullRequestResolver.parseGitHub(github).map(\.branch) == ["feat"])
        #expect(PullRequestResolver.parseGitLab(gitlab).map(\.branch) == ["feat"])
    }

    private func request(_ branch: String, _ state: PullRequestState, sha: String? = nil) -> PullRequest {
        PullRequest(
            url: URL(string: "https://github.com/a/b/pull/\(branch)-\(state)")!, state: state, branch: branch,
            headSHA: sha)
    }

    @Test func prefersOpenThenMergedThenClosedForABranch() {
        let closed = request("feat", .closed)
        let merged = request("feat", .merged)
        let open = request("feat", .open)
        let newerMerged = request("feat", .merged, sha: "n")

        #expect(PullRequest.best(forBranch: "feat", head: nil, in: [closed, merged, open]) == open)
        #expect(PullRequest.best(forBranch: "feat", head: nil, in: [closed, merged]) == merged)
        #expect(PullRequest.best(forBranch: "feat", head: nil, in: [closed]) == closed)
        // Within a state, the first listed (most recent) wins.
        #expect(PullRequest.best(forBranch: "feat", head: nil, in: [newerMerged, merged]) == newerMerged)
        #expect(PullRequest.best(forBranch: "other", head: nil, in: [closed, merged, open]) == nil)
    }

    @Test func findsTheRequestOfADetachedWorktreeByCommit() {
        let target = request("feat/a", .merged, sha: "abc123")
        let requests = [request("feat/b", .open, sha: "fff"), target, request("feat/c", .open)]

        #expect(PullRequest.best(forBranch: nil, head: "abc123", in: requests) == target)
        #expect(PullRequest.best(forBranch: nil, head: "000000", in: requests) == nil)
        #expect(PullRequest.best(forBranch: nil, head: nil, in: requests) == nil)
        // A reused branch name: a merged request that ended at another commit is not this worktree's.
        let old = request("feat/old", .merged, sha: "111")
        #expect(PullRequest.best(forBranch: "feat/old", head: "222", in: [old]) == nil)
        #expect(PullRequest.best(forBranch: "feat/old", head: "111", in: [old]) == old)
        // The main worktree only counts open requests.
        #expect(PullRequest.best(forBranch: "feat/old", head: "111", isMain: true, in: [old]) == nil)
        #expect(
            PullRequest.best(forBranch: "feat/b", head: "x", isMain: true, in: requests)?.branch == "feat/b")
        // A worktree on a branch is never matched by commit, even when its HEAD equals another request's head.
        #expect(PullRequest.best(forBranch: "feat/b", head: "abc123", in: requests)?.branch == "feat/b")
        #expect(PullRequest.best(forBranch: "main", head: "abc123", in: requests) == nil)
    }

    /// A stand-in `gh` / `glab` that records its arguments, so the exact command line is checked.
    private func fakeTool(_ fixture: GitFixture, output: String) throws -> (path: String, argsFile: URL) {
        let script = fixture.root.appending(path: "fake-tool")
        let argsFile = fixture.root.appending(path: "args.txt")
        try "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(argsFile.path)'\ncat <<'E'\n\(output)\nE\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (script.path, argsFile)
    }

    @Test func asksGitHubForTheRepoItsRemoteNames() async throws {
        let fixture = try GitFixture()
        let tool = try fakeTool(
            fixture,
            output:
                #"[{"headRefName":"b","url":"https://github.com/a/b/pull/1","state":"OPEN"},{"headRefName":"m","url":"https://github.com/a/b/pull/2","state":"MERGED"}]"#
        )
        let remote = try #require(RepoRemote(remoteURL: "git@github.com:a/b.git"))
        let resolver = PullRequestResolver(tools: ToolPaths(gh: tool.path))

        let requests = try await resolver.requests(for: remote, in: fixture.root)

        #expect(requests.map(\.state) == [.open, .merged])
        let args = try String(contentsOf: tool.argsFile, encoding: .utf8).split(separator: "\n").map(
            String.init)
        #expect(args.starts(with: ["pr", "list", "-R", "github.com/a/b", "--state", "all"]))
        #expect(args.contains("headRefName,headRefOid,url,state,title,isCrossRepository"))
    }

    @Test func asksSelfHostedGitLabByFullURL() async throws {
        let fixture = try GitFixture()
        let tool = try fakeTool(
            fixture,
            output:
                #"[{"source_branch":"b","web_url":"https://gitlab.corp.example/t/a/-/merge_requests/2","state":"merged"}]"#
        )
        let remote = try #require(RepoRemote(remoteURL: "git@gitlab.corp.example:t/a.git"))

        let result = try await PullRequestResolver(tools: ToolPaths(glab: tool.path)).requests(
            for: remote, in: fixture.root)

        #expect(result.map(\.state) == [.merged])
        let args = try String(contentsOf: tool.argsFile, encoding: .utf8).split(separator: "\n").map(
            String.init)
        #expect(args.starts(with: ["mr", "list", "-R", "https://gitlab.corp.example/t/a", "--all"]))
    }

    @Test(arguments: [
        (
            "git@github.com:a/b.git", "body",
            ["pr", "view", "https://github.com/a/b/pull/7", "--json", "body"]
        ),
        (
            "git@gitlab.corp.example:t/a.git", "description",
            ["mr", "view", "7", "-R", "https://gitlab.corp.example/t/a", "-F", "json"]
        ),
    ])
    func readsTheDescriptionCappedAndTrimmed(remoteURL: String, key: String, expectedArgs: [String])
        async throws
    {
        let fixture = try GitFixture()
        let tool = try fakeTool(
            fixture, output: #"{"\#(key)":"  \#(String(repeating: "z", count: 3000))\n"}"#)
        let remote = try #require(RepoRemote(remoteURL: remoteURL))
        let url = try #require(URL(string: "\(remote.webURL!.absoluteString)/pull/7"))
        let request = PullRequest(url: url, state: .merged, branch: "b")
        let resolver = PullRequestResolver(tools: ToolPaths(gh: tool.path, glab: tool.path))

        let text = await resolver.description(of: request, on: remote, in: fixture.root)

        #expect(text == String(repeating: "z", count: 2000))
        let args = try String(contentsOf: tool.argsFile, encoding: .utf8).split(separator: "\n").map(
            String.init)
        #expect(args == expectedArgs)
    }

    @Test func descriptionFailuresAreSilent() async throws {
        let fixture = try GitFixture()
        let remote = try #require(RepoRemote(remoteURL: "git@github.com:a/b.git"))
        let request = PullRequest(
            url: URL(string: "https://github.com/a/b/pull/7")!, state: .open, branch: "b")
        let broken = fixture.root.appending(path: "broken")
        try "#!/bin/sh\necho nope >&2\nexit 1\n".write(to: broken, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: broken.path)

        let missingTool = await PullRequestResolver(tools: ToolPaths()).description(
            of: request, on: remote, in: fixture.root)
        let failingTool = await PullRequestResolver(tools: ToolPaths(gh: broken.path)).description(
            of: request, on: remote, in: fixture.root)

        #expect(missingTool == nil && failingTool == nil)
    }

    @Test func missingToolIsReportedNotSwallowed() async throws {
        let remote = try #require(RepoRemote(remoteURL: "git@github.com:a/b.git"))
        await #expect(throws: PullRequestError.toolMissing("gh")) {
            try await PullRequestResolver(tools: ToolPaths()).requests(
                for: remote, in: URL(fileURLWithPath: "/"))
        }
    }
}
