import Foundation

public enum Forge: String, Equatable, Sendable {
    case github, gitlab
}

/// A repository's origin on a forge, parsed from the remote URL of the repo being looked at.
public struct RepoRemote: Equatable, Sendable {
    public let host: String
    /// `owner/repo` or `group/subgroup/repo`, without `.git`.
    public let path: String
    /// Nil for a host that is neither GitHub nor GitLab: no web button then.
    public let forge: Forge?

    public var webURL: URL? { URL(string: "https://\(host)/\(path)") }

    /// `gitlabHosts` / `githubHosts` name self-hosted instances whose host does not say which forge it is
    /// (read from `glab auth status` / `gh auth status`).
    public init?(remoteURL: String, gitlabHosts: Set<String> = [], githubHosts: Set<String> = []) {
        guard let (host, path) = Self.split(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let lowered = host.lowercased()
        self.host = lowered
        self.path = path
        if gitlabHosts.contains(lowered) || lowered.contains("gitlab") {
            forge = .gitlab
        } else if githubHosts.contains(lowered) || lowered.contains("github") {
            forge = .github
        } else {
            forge = nil
        }
    }

    /// Handles `git@host:group/repo.git`, `ssh://git@host:2222/group/repo.git`, `https://user:token@host/group/repo`.
    private static func split(_ raw: String) -> (String, String)? {
        var host: String
        var path: String
        if raw.contains("://") {
            guard let components = URLComponents(string: raw), let h = components.host else { return nil }
            host = h
            path = components.path
        } else if let colon = raw.firstIndex(of: ":") {
            host = String(raw[..<colon])
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            path = String(raw[raw.index(after: colon)...])
        } else {
            return nil
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix(".git") { path = String(path.dropLast(4)) }
        return host.isEmpty || path.isEmpty ? nil : (host, path)
    }
}

extension GitClient {
    /// URL of `origin`, else of the first remote; nil when the repo has no remote.
    public func remoteURL(of repo: URL) async throws -> String? {
        for name in ["origin"] + (try await remoteNames(of: repo)) {
            let out = try await run(["remote", "get-url", name], in: repo, accepting: [0, 2, 128])
            if out.status == 0 { return out.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return nil
    }

    private func remoteNames(of repo: URL) async throws -> [String] {
        try await git(["remote"], in: repo).stdoutString.split(separator: "\n").map(String.init)
    }
}
