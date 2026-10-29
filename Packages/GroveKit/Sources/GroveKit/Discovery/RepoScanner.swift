import Foundation

/// Finds main repositories under user-chosen roots. Never looks outside them.
public struct RepoScanner: Sendable {
    public static let skippedDirectories: Set<String> = [
        "node_modules", ".build", "Pods", "DerivedData", "vendor", "target", "dist", "build", "venv",
    ]

    private let maxDepth: Int

    public init(maxDepth: Int = 4) {
        self.maxDepth = maxDepth
    }

    /// A directory with a `.git` *directory* is a main repo. A `.git` *file* is a linked worktree or a
    /// submodule: skipped here, worktrees come from their main repo's `git worktree list`.
    /// shortcut: repos nested inside another repo are not found, add a scan of submodule-less subtrees if needed.
    /// Synchronous disk walk: call it off the main actor.
    public func repositories(under roots: [URL]) -> [URL] {
        var found: [URL] = []
        for root in roots { scan(root, depth: 0, into: &found) }
        // Overlapping roots (`~/src` and `~/src/work`) must not list a repo twice.
        var seen = Set<String>()
        return found.filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
            .sorted { $0.path < $1.path }
    }

    private func scan(_ directory: URL, depth: Int, into found: inout [URL]) {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: directory.appending(path: ".git").path, isDirectory: &isDirectory) {
            if isDirectory.boolValue { found.append(directory) }
            return
        }
        // Noise folders are skipped only after the repo check above: a repo may be called `vendor`.
        guard depth < maxDepth, !Self.skippedDirectories.contains(directory.lastPathComponent),
            let children = try? fileManager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles])
        else { return }
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            scan(child, depth: depth + 1, into: &found)
        }
    }
}
