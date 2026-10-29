import Foundation

public enum PullRequestError: Error, Equatable, LocalizedError {
    case toolMissing(String)
    case failed(tool: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .toolMissing(let tool): "`\(tool)` est introuvable : les PR/MR ne peuvent pas être affichées."
        case .failed(let tool, let detail): "`\(tool)` a échoué : \(detail)"
        }
    }
}

/// Pull requests / merge requests of one repo through the user's own `gh` / `glab` login (no token is stored
/// by Grove). One call per repo, not per worktree.
public struct PullRequestResolver: Sendable {
    private let tools: ToolPaths
    private let runner = ProcessRunner(environment: ["GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"])

    public init(tools: ToolPaths) {
        self.tools = tools
    }

    /// Open, merged and closed requests: every open one (a dedicated call, so a long-lived open request is never
    /// pushed out by newer merged ones), then the most recent of all states. The `limit` / `-P` caps are the
    /// `best(forBranch:)` shortcut.
    public func requests(for remote: RepoRemote, in repo: URL) async throws -> [PullRequest] {
        let open = try await fetch(remote, in: repo, includingClosed: false)
        let all = try await fetch(remote, in: repo, includingClosed: true)
        var seen = Set(open.map(\.url))
        return open + all.filter { seen.insert($0.url).inserted }
    }

    private func fetch(_ remote: RepoRemote, in repo: URL, includingClosed: Bool) async throws
        -> [PullRequest]
    {
        switch remote.forge {
        case .github:
            let data = try await run(
                tool: ("gh", tools.gh),
                [
                    "pr", "list", "-R", "\(remote.host)/\(remote.path)", "--state",
                    includingClosed ? "all" : "open", "--json",
                    "headRefName,headRefOid,url,state,title,isCrossRepository", "--limit", "200",
                ],
                in: repo)
            return Self.parseGitHub(data)
        case .gitlab:
            // The full URL makes glab talk to the right (self-hosted) instance.
            let data = try await run(
                tool: ("glab", tools.glab),
                ["mr", "list", "-R", "https://\(remote.host)/\(remote.path)"]
                    + (includingClosed ? ["--all"] : []) + ["-F", "json", "-P", "100"],
                in: repo)
            return Self.parseGitLab(data)
        case nil:
            return []
        }
    }

    /// Description of one request, capped; nil on any failure (it is optional context, never an error).
    public func description(
        of request: PullRequest, on remote: RepoRemote, in repo: URL, limit: Int = 2000
    ) async -> String? {
        let data: Data?
        let key: String
        switch remote.forge {
        case .github:
            key = "body"
            data = try? await run(
                tool: ("gh", tools.gh), ["pr", "view", request.url.absoluteString, "--json", key], in: repo)
        case .gitlab:
            key = "description"
            guard let number = request.number else { return nil }
            data = try? await run(
                tool: ("glab", tools.glab),
                ["mr", "view", String(number), "-R", "https://\(remote.host)/\(remote.path)", "-F", "json"],
                in: repo)
        case nil:
            return nil
        }
        guard let data, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else { return nil }
        return String(text.prefix(limit))
    }

    static func parseGitHub(_ data: Data) -> [PullRequest] {
        parse(
            data, branchKey: "headRefName", shaKey: "headRefOid", urlKey: "url",
            states: ["OPEN": .open, "MERGED": .merged, "CLOSED": .closed]
        ) { $0["isCrossRepository"] as? Bool != true }
    }

    static func parseGitLab(_ data: Data) -> [PullRequest] {
        parse(
            data, branchKey: "source_branch", shaKey: "sha", urlKey: "web_url",
            states: ["opened": .open, "merged": .merged, "closed": .closed]
        ) {
            // A merge request from a fork has a different source project.
            ($0["source_project_id"] as? Int) == ($0["target_project_id"] as? Int)
        }
    }

    /// `keep` drops requests that do not come from this repo itself (forks): their branch names are not ours.
    /// A request with an unknown state is dropped too.
    private static func parse(
        _ data: Data, branchKey: String, shaKey: String, urlKey: String,
        states: [String: PullRequestState], keep: ([String: Any]) -> Bool
    ) -> [PullRequest] {
        guard let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.filter(keep).compactMap { item in
            guard let branch = item[branchKey] as? String, let raw = item[urlKey] as? String,
                let url = URL(string: raw), let state = (item["state"] as? String).flatMap({ states[$0] })
            else { return nil }
            return PullRequest(
                url: url, state: state, branch: branch, headSHA: item[shaKey] as? String,
                title: item["title"] as? String)
        }
    }

    private func run(tool: (name: String, path: String?), _ arguments: [String], in repo: URL) async throws
        -> Data
    {
        guard let path = tool.path else { throw PullRequestError.toolMissing(tool.name) }
        let out = try await runner.run(path, arguments, cwd: repo, timeout: .seconds(30))
        guard out.status == 0 else {
            throw PullRequestError.failed(
                tool: tool.name, detail: out.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return out.stdout
    }
}
