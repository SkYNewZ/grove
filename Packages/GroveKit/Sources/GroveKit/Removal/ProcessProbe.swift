import Foundation

/// Finds processes (a `claude` session, a shell) whose working directory is inside a worktree.
public struct ProcessProbe: Sendable {
    private let runner = ProcessRunner()

    public init() {}

    /// Best effort: only the user's own processes are visible, and a missing `lsof` yields no result.
    public func processes(withCwdUnder path: String) async -> [String] {
        guard
            let out = try? await runner.run(
                "/usr/sbin/lsof", ["-d", "cwd", "-Fpcn"], cwd: URL(fileURLWithPath: "/"),
                timeout: .seconds(10))
        else { return [] }
        var pid = ""
        var command = ""
        var found: [String] = []
        for line in out.stdoutString.split(separator: "\n") {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = value
            case "c": command = value
            case "n":
                if PathIdentity.isInside(value, directory: path) { found.append("\(command) (\(pid))") }
            default: break
            }
        }
        return found
    }
}
