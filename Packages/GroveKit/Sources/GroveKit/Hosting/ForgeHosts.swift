import Foundation

/// Self-hosted instances the user is logged in to, read from `gh auth status` / `glab auth status`.
/// Lets `git.company.example` count as GitLab although its name does not say so.
public struct ForgeHosts: Equatable, Sendable {
    public var github: Set<String> = []
    public var gitlab: Set<String> = []

    public init(github: Set<String> = [], gitlab: Set<String> = []) {
        self.github = github
        self.gitlab = gitlab
    }

    public static func discover(tools: ToolPaths) async -> ForgeHosts {
        async let github = hosts(tool: tools.gh)
        async let gitlab = hosts(tool: tools.glab)
        return await ForgeHosts(github: github, gitlab: gitlab)
    }

    static func parse(_ text: String) -> Set<String> {
        Set(text.matches(of: #/Logged in to (\S+)/#).map { $0.1.lowercased() })
    }

    private static func hosts(tool: String?) async -> Set<String> {
        guard let tool,
            let out = try? await ProcessRunner().run(
                tool, ["auth", "status"], cwd: URL(fileURLWithPath: "/"), timeout: .seconds(15))
        else { return [] }
        // Both tools print the report on stderr, and exit non-zero when any one host is broken.
        return parse(out.stdoutString + out.stderr)
    }
}
