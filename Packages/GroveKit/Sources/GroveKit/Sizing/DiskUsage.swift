import Foundation

public struct RepoSizes: Equatable, Sendable {
    /// Allocated bytes per worktree path, nested worktrees excluded from their parent.
    public let perWorktree: [String: Int64]
    public var total: Int64 { perWorktree.values.reduce(0, +) }
}

/// Disk space as Finder counts it: allocated blocks, symlinks not followed.
public enum DiskUsage {
    /// Sizes every worktree of a repo off the main thread. The main working copy does not include the
    /// worktrees nested inside it (`.claude/worktrees/*`), so `total` counts nothing twice.
    public static func measure(_ worktrees: [Worktree]) async -> RepoSizes {
        let paths = worktrees.map(\.path)
        var sizes: [String: Int64] = [:]
        await withTaskGroup(of: (String, Int64).self) { group in
            for path in paths where FileManager.default.fileExists(atPath: path) {
                let others = paths.filter { !PathIdentity.same($0, path) }
                group.addTask(priority: .utility) {
                    (path, allocatedSize(of: URL(fileURLWithPath: path), excluding: others))
                }
            }
            for await (path, size) in group { sizes[path] = size }
        }
        return RepoSizes(perWorktree: sizes)
    }

    /// Allocated bytes under `directory`, skipping subtrees listed in `excluding` (paths).
    public static func allocatedSize(of directory: URL, excluding: [String] = []) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard
            let walker = FileManager.default.enumerator(
                at: directory, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true })
        else { return 0 }
        let skipped = excluding.filter { PathIdentity.isInside($0, directory: directory.path) }
        let skippedNames = Set(skipped.map { URL(fileURLWithPath: $0).lastPathComponent })
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true, skippedNames.contains(url.lastPathComponent),
                skipped.contains(where: { PathIdentity.same($0, url.path) })
            {
                walker.skipDescendants()
                continue
            }
            total += Int64(values?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
