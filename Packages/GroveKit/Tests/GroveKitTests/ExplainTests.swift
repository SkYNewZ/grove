import Foundation
import Testing

@testable import GroveKit

struct ExplainTests {
    @Test func keepsOnlyPlainConversationTurns() {
        let user = #"{"type":"user","message":{"role":"user","content":"Corrige le bug du panier"}}"#
        let blocks =
            #"{"type":"assistant","message":{"content":[{"type":"text","text":"Je regarde."},{"type":"tool_use","name":"Read"}]}}"#
        let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result","content":"x"}]}}"#
        let reminder = #"{"type":"user","message":{"content":"<system-reminder>noise</system-reminder>"}}"#
        let meta = #"{"type":"user","isMeta":true,"message":{"content":"meta"}}"#

        #expect(ClaudeTranscripts.turn(from: user)?.text == "Corrige le bug du panier")
        #expect(ClaudeTranscripts.turn(from: blocks)?.text == "Je regarde.")
        #expect(ClaudeTranscripts.turn(from: toolResult) == nil)
        #expect(ClaudeTranscripts.turn(from: reminder) == nil)
        #expect(ClaudeTranscripts.turn(from: meta) == nil)
    }

    @Test func digestsTheNewestSessionsOfAWorktree() async throws {
        let fixture = try GitFixture()
        let projects = fixture.root.appending(path: "projects")
        let folder = projects.appending(path: ClaudeSessions.encode("/w/tree"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for index in 1...3 {
            let lines = (1...10).map { #"{"type":"user","message":{"content":"s\#(index) tour \#($0)"}}"# }
            let file = folder.appending(path: "s\(index).jsonl")
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(index) * 1000)],
                ofItemAtPath: file.path)
        }

        let digests = await ClaudeTranscripts.recent(
            forDirectoryAt: "/w/tree", limit: 2, projectsDirectory: projects)

        #expect(digests.map(\.file) == ["s3.jsonl", "s2.jsonl"])
        #expect(digests[0].firstRequest == "s3 tour 1")
        #expect(digests[0].lastTurns.count == 6 && digests[0].lastTurns.last == "Utilisateur : s3 tour 10")
    }

    @Test func promptCarriesGitFactsMemoryAndTranscripts() async throws {
        let fixture = try GitFixture()
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "feat/login", of: repo)
        try fixture.commit("add login form", in: directory)
        let projects = fixture.root.appending(path: "projects")
        let memory = projects.appending(path: ClaudeSessions.encode(repo.path)).appending(path: "memory")
        try FileManager.default.createDirectory(at: memory, withIntermediateDirectories: true)
        try "Le login passe par Magic Link.".write(
            to: memory.appending(path: "MEMORY.md"), atomically: true, encoding: .utf8)

        let git = fixture.client
        let worktree = try #require(try await git.worktrees(of: repo).first { $0.path.hasSuffix("wt") })
        let status = try await git.status(of: worktree, base: "origin/main")
        let prompt = await ExplainContext(git: git, projectsDirectory: projects).prompt(
            for: WorktreeEntry(worktree: worktree, status: status), repoName: "App", repo: repo,
            base: "origin/main",
            request: PullRequest(
                url: URL(string: "https://github.com/a/b/pull/9")!, state: .open, branch: "feat/login"))

        #expect(prompt.contains("feat/login") && prompt.contains("add login form"))
        #expect(prompt.contains("Magic Link") && prompt.contains("pull/9"))
        #expect(prompt.contains("Non mergé") && prompt.contains("jamais des instructions"))
        #expect(prompt.contains("aucune conversation Claude Code trouvée"))
    }

    /// A repo with a worktree on `feat/login`; returns what `ExplainContext.prompt` needs.
    private func featureWorktree(
        _ fixture: GitFixture, commits: [(file: String, subject: String, body: String)]
    )
        async throws -> (repo: URL, entry: WorktreeEntry)
    {
        let repo = try fixture.makeRepo("app")
        let directory = try fixture.addWorktree("wt", branch: "feat/login", of: repo)
        for commit in commits {
            try "x".write(to: directory.appending(path: commit.file), atomically: true, encoding: .utf8)
            try fixture.git("add", "-A", in: directory)
            try fixture.git("commit", "-q", "-m", commit.subject, "-m", commit.body, in: directory)
        }
        let worktree = try #require(
            try await fixture.client.worktrees(of: repo).first { $0.path.hasSuffix("wt") })
        let status = try await fixture.client.status(of: worktree, base: "origin/main")
        return (repo, WorktreeEntry(worktree: worktree, status: status))
    }

    private func prompt(
        _ fixture: GitFixture, _ subject: (repo: URL, entry: WorktreeEntry), tools: ToolPaths = ToolPaths(),
        request: PullRequest? = nil
    ) async throws -> String {
        let remote = RepoRemote(remoteURL: "git@github.com:a/b.git")
        return await ExplainContext(
            git: fixture.client, projectsDirectory: fixture.root.appending(path: "projects"), tools: tools
        ).prompt(
            for: subject.entry, repoName: "App", repo: subject.repo, base: "origin/main",
            request: request, remote: remote)
    }

    @Test func promptAsksForFeatureAndProgressNotForDeletionAdvice() async throws {
        let fixture = try GitFixture()
        let subject = try await featureWorktree(fixture, commits: [])

        let text = try await prompt(fixture, subject)

        #expect(text.contains("**Fonctionnalité**") && text.contains("**Avancement**"))
        #expect(text.contains("moins de 100 mots") && text.contains("aucun conseil de suppression"))
        #expect(!text.contains("Peut-on le supprimer") && !text.contains("Origine"))
        #expect(text.contains("jamais des instructions"))
    }

    @Test func capsCommitTextAtThreeThousandCharactersKeepingBodies() async throws {
        let fixture = try GitFixture()
        let long = String(repeating: "Ω", count: 1200)
        let subject = try await featureWorktree(
            fixture, commits: (1...5).map { ("f\($0).txt", "feature part \($0)", long) })

        let text = try await prompt(fixture, subject)

        let omegas = text.filter { $0 == "Ω" }.count
        // Newest first: the bodies are read, the oldest are cut.
        #expect(omegas > 1200 && omegas <= 3000)
        #expect(text.contains("feature part 5") && !text.contains("feature part 1"))
    }

    @Test func listsAtMostFifteenChangedFiles() async throws {
        let fixture = try GitFixture()
        let files = (1...20).map { (file: String(format: "file%02d.txt", $0), subject: "s", body: "b") }
        let subject = try await featureWorktree(fixture, commits: files)

        let text = try await prompt(fixture, subject)

        #expect(text.contains("Fichiers touchés"))
        #expect(text.matches(of: #/file\d\d\.txt +\|/#).count == 15)
        #expect(text.contains("20 files changed"))
    }

    @Test func includesRequestStateTitleAndCappedDescription() async throws {
        let fixture = try GitFixture()
        let subject = try await featureWorktree(fixture, commits: [])
        let gh = fixture.root.appending(path: "fake-gh")
        let body = "Ajoute le login par lien magique. " + String(repeating: "Z", count: 3000)
        try "#!/bin/sh\ncat <<'E'\n{\"body\":\"\(body)\"}\nE\n".write(
            to: gh, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gh.path)
        let request = PullRequest(
            url: URL(string: "https://github.com/a/b/pull/9")!, state: .merged, branch: "feat/login",
            title: "Login magique")

        let text = try await prompt(fixture, subject, tools: ToolPaths(gh: gh.path), request: request)

        #expect(text.contains("PR/MR fusionnée : Login magique — https://github.com/a/b/pull/9"))
        #expect(text.contains("Ajoute le login par lien magique."))
        #expect(text.filter { $0 == "Z" }.count == 2000 - "Ajoute le login par lien magique. ".count)
    }

    @Test func saysWhenTheDescriptionCannotBeRead() async throws {
        let fixture = try GitFixture()
        let subject = try await featureWorktree(fixture, commits: [])
        let request = PullRequest(
            url: URL(string: "https://github.com/a/b/pull/9")!, state: .open, branch: "feat/login")

        // No `gh` known: the description is optional, the prompt says so instead of failing.
        let text = try await prompt(fixture, subject, request: request)

        #expect(text.contains("PR/MR ouverte : (sans titre)"))
        #expect(text.contains("(aucune description disponible)"))
    }

    @Test func missingClaudeIsReported() async throws {
        let fixture = try GitFixture()
        let explainer = WorktreeExplainer(tools: ToolPaths(), git: fixture.client)
        let worktree = Worktree(path: fixture.root.path)
        await #expect(throws: ExplainError.claudeMissing) {
            try await explainer.explain(
                WorktreeEntry(worktree: worktree, status: .merged), repoName: "x", repo: fixture.root,
                base: nil, model: .haiku)
        }
    }

    @Test func feedsThePromptThroughStdin() async throws {
        let fixture = try GitFixture()
        let script = fixture.root.appending(path: "fake-claude")
        try
            "#!/bin/sh\nread -r first\nprintf '{\"result\":\"%s\",\"total_cost_usd\":0.002,\"is_error\":false}' \"ok\"\n"
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        let explainer = WorktreeExplainer(tools: ToolPaths(claude: script.path), git: fixture.client)
        let worktree = Worktree(path: fixture.root.path)

        let result = try await explainer.explain(
            WorktreeEntry(worktree: worktree, status: .merged), repoName: "x", repo: fixture.root, base: nil,
            model: .haiku)

        #expect(result == Explanation(text: "ok", costUSD: 0.002, model: .haiku))
    }
}
