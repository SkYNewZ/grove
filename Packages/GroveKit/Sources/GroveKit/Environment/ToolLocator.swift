import Foundation

/// Absolute paths of the command-line tools Grove drives. A GUI app does not inherit the user's shell PATH,
/// so these are resolved once through a login shell and cached by the caller.
public struct ToolPaths: Equatable, Sendable {
    public var git: String?
    public var gh: String?
    public var glab: String?
    public var claude: String?

    public init(git: String? = nil, gh: String? = nil, glab: String? = nil, claude: String? = nil) {
        self.git = git
        self.gh = gh
        self.glab = glab
        self.claude = claude
    }
}

public enum ToolLocator {
    private static let names = ["git", "gh", "glab", "claude"]

    public static func locate() async -> ToolPaths {
        var found = await fromLoginShell()
        for name in names where found[name] == nil {
            found[name] = searchDirectories(for: name)
        }
        return ToolPaths(git: found["git"], gh: found["gh"], glab: found["glab"], claude: found["claude"])
    }

    /// `zsh -lic` so both `.zprofile` (Homebrew) and `.zshrc` (`~/.local/bin`) are read.
    private static func fromLoginShell() async -> [String: String] {
        let script =
            "for t in \(names.joined(separator: " ")); do printf '@@%s=%s\\n' $t \"$(command -v $t)\"; done"
        guard
            let out = try? await ProcessRunner().run(
                "/bin/zsh", ["-lic", script], cwd: URL(fileURLWithPath: "/"), timeout: .seconds(8))
        else { return [:] }
        var result: [String: String] = [:]
        for line in out.stdoutString.split(separator: "\n") where line.hasPrefix("@@") {
            let pair = line.dropFirst(2).split(separator: "=", maxSplits: 1)
            // An alias or function prints text instead of a path: only executable files count.
            if pair.count == 2, FileManager.default.isExecutableFile(atPath: String(pair[1])) {
                result[String(pair[0])] = String(pair[1])
            }
        }
        return result
    }

    private static func searchDirectories(for name: String) -> String? {
        let home = NSHomeDirectory()
        let directories = [
            "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local", "/usr/bin",
        ]
        return directories.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
