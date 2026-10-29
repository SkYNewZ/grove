import Foundation

public enum ExplainModel: String, CaseIterable, Sendable {
    case haiku, sonnet
}

public struct Explanation: Equatable, Sendable {
    public let text: String
    public let costUSD: Double?
    public let model: ExplainModel
}

public enum ExplainError: Error, Equatable, LocalizedError {
    case claudeMissing
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .claudeMissing: "La commande `claude` est introuvable."
        case .failed(let detail): "L'explication a échoué : \(detail)"
        }
    }
}

/// Asks Claude (headless `claude -p`, tools off, no session saved) to explain a worktree. Cheap by design:
/// Haiku by default, a hard budget cap per call, and the cost is reported back.
public struct WorktreeExplainer: Sendable {
    private let tools: ToolPaths
    private let context: ExplainContext
    /// shortcut: one flat cap per call; lower it if Sonnet on a huge transcript ever reaches it.
    private let budgetUSD: Double

    public init(tools: ToolPaths, git: GitClient, budgetUSD: Double = 0.25) {
        self.tools = tools
        self.context = ExplainContext(git: git, tools: tools)
        self.budgetUSD = budgetUSD
    }

    public func explain(
        _ entry: WorktreeEntry, repoName: String, repo: URL, base: String?,
        request: PullRequest? = nil, remote: RepoRemote? = nil, model: ExplainModel
    ) async throws -> Explanation {
        guard let claude = tools.claude else { throw ExplainError.claudeMissing }
        let prompt = await context.prompt(
            for: entry, repoName: repoName, repo: repo, base: base, request: request, remote: remote)
        let arguments = [
            "-p", "--model", model.rawValue, "--tools", "", "--no-session-persistence", "--output-format",
            "json",
            "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
            "--max-budget-usd", String(budgetUSD),
        ]
        let out = try await ProcessRunner(environment: ["PATH": searchPath()]).run(
            claude, arguments, cwd: URL(fileURLWithPath: NSTemporaryDirectory()), input: Data(prompt.utf8),
            timeout: .seconds(180))
        guard let object = try? JSONSerialization.jsonObject(with: out.stdout) as? [String: Any] else {
            throw ExplainError.failed(out.stderr.isEmpty ? "réponse illisible" : out.stderr)
        }
        let text = (object["result"] as? String) ?? ""
        guard object["is_error"] as? Bool != true, !text.isEmpty else {
            throw ExplainError.failed(text.isEmpty ? "réponse vide" : text)
        }
        return Explanation(text: text, costUSD: object["total_cost_usd"] as? Double, model: model)
    }

    /// A GUI app has a bare PATH: give the child the directories of the tools Grove found.
    private func searchPath() -> String {
        let found = [tools.claude, tools.git, tools.gh, tools.glab].compactMap { $0 }
            .map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
        var seen = Set<String>()
        return (found + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"])
            .filter { seen.insert($0).inserted }.joined(separator: ":")
    }
}
