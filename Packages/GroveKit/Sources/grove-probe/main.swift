import Foundation
import GroveKit

// Read-only command-line probe of GroveKit on real folders: `grove-probe [--no-sizes] <root>...`.
// Used to check the scan against `git worktree list` and to time it with hyperfine.
let arguments = Array(CommandLine.arguments.dropFirst())
let withSizes = !arguments.contains("--no-sizes")
let explainPath = arguments.firstIndex(of: "--explain").flatMap {
    arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
}
let roots = arguments.filter { !$0.hasPrefix("--") && $0 != explainPath }.map { URL(fileURLWithPath: $0) }

let tools = await ToolLocator.locate()
let git = GitClient(gitPath: tools.git ?? "/usr/bin/git")
let megabytes = { (bytes: Int64) in String(format: "%.0f MB", Double(bytes) / 1_048_576) }

let snapshots = await RepoLoader.load(roots: roots, git: git)
var sizes: [String: RepoSizes] = [:]
if withSizes {
    await withTaskGroup(of: (String, RepoSizes).self) { group in
        for snapshot in snapshots {
            group.addTask { (snapshot.id, await DiskUsage.measure(snapshot.entries.map(\.worktree))) }
        }
        for await (id, size) in group { sizes[id] = size }
    }
}
for snapshot in snapshots {
    let repoSizes = sizes[snapshot.id]
    print("\(snapshot.name)  \(snapshot.url.path)  \(repoSizes.map { megabytes($0.total) } ?? "")")
    if let error = snapshot.error { print("    ERROR \(error)") }
    for entry in snapshot.entries {
        let size = repoSizes?.perWorktree[entry.worktree.path].map(megabytes) ?? ""
        let branch = entry.worktree.branch ?? "detached"
        print("    \(entry.worktree.path)  [\(branch)]  \(entry.status)  \(size)")
    }
}

if let explainPath {
    guard let repo = snapshots.first(where: { $0.entries.contains { $0.worktree.path == explainPath } }),
        let entry = repo.entries.first(where: { $0.worktree.path == explainPath })
    else { fatalError("no worktree at \(explainPath) under the given roots") }
    let base = try await git.defaultBase(of: repo.url)
    let result = try await WorktreeExplainer(tools: tools, git: git).explain(
        entry, repoName: repo.name, repo: repo.url, base: base, model: .haiku)
    print(
        "\n--- explain (\(result.model), \(result.costUSD.map { String(format: "%.4f $", $0) } ?? "?")) ---\n\(result.text)"
    )
}
