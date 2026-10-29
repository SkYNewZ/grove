import Foundation

public struct Worktree: Equatable, Sendable {
    public var path: String
    /// The repo's own working copy (git always lists it first).
    public var isMain = false
    public var head: String?
    /// Short branch name (`feature/x`), nil when detached or bare.
    public var branch: String?
    public var isBare = false
    public var isDetached = false
    /// Non-nil when locked; empty string when git gave no reason.
    public var lockReason: String?
    /// Non-nil when git considers the entry prunable (directory missing, ...).
    public var prunableReason: String?

    public var isLocked: Bool { lockReason != nil }
    public var directoryName: String { URL(fileURLWithPath: path).lastPathComponent }
    /// Codex nests the checkout (`~/.codex/worktrees/<id>/<repo>`): the id is what tells two of them apart.
    public var displayName: String {
        guard origin == .codex, let range = path.range(of: "/.codex/worktrees/") else { return directoryName }
        return path[range.upperBound...].split(separator: "/").first.map(String.init) ?? directoryName
    }
    public var origin: WorktreeOrigin? { WorktreeOrigin.detect(path: path) }

    public init(path: String) {
        self.path = path
    }
}

/// Parses `git worktree list --porcelain -z`: NUL-terminated fields, every record starts with `worktree`.
public enum WorktreeListParser {
    public static func parse(_ data: Data) -> [Worktree] {
        var result: [Worktree] = []
        for field in data.split(separator: 0) {
            let parts = String(decoding: field, as: UTF8.self)
                .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
            let key = parts[0]
            let value = parts.count > 1 ? String(parts[1]) : ""
            if key == "worktree" {
                result.append(Worktree(path: value))
                continue
            }
            guard let last = result.indices.last else { continue }
            switch key {
            case "HEAD": result[last].head = value
            case "branch": result[last].branch = String(value.trimmingPrefix("refs/heads/"))
            case "bare": result[last].isBare = true
            case "detached": result[last].isDetached = true
            case "locked": result[last].lockReason = value
            case "prunable": result[last].prunableReason = value
            default: break
            }
        }
        if !result.isEmpty { result[0].isMain = true }
        return result
    }
}
