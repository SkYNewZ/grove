import Foundation

/// The tool that created a worktree, told from where it lives.
public enum WorktreeOrigin: Sendable {
    case claudeCode, codex

    /// `<repo>/.claude/worktrees/<name>` for Claude Code, `<home>/.codex/worktrees/…` for Codex; nil for a
    /// worktree the user made by hand.
    public static func detect(path: String, home: String = NSHomeDirectory()) -> WorktreeOrigin? {
        if path.contains("/.claude/worktrees/") { return .claudeCode }
        if path.hasPrefix(URL(fileURLWithPath: home).appending(path: ".codex/worktrees").path + "/") {
            return .codex
        }
        return nil
    }
}
