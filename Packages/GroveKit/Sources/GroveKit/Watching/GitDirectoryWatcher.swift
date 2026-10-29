import CoreServices
import Foundation

/// Reports repos whose worktree list changed (`git worktree add/remove/prune`), through FSEvents on their `.git`.
/// shortcut: a worktree folder deleted by hand changes nothing under `.git`; the app also refreshes on activation.
public final class GitDirectoryWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "grove.git-watcher")
    private let handler: @Sendable (URL) -> Void
    private let repos: [URL]

    /// `handler` receives the main repo URL of each change, on a background queue.
    public init(repos: [URL], latency: TimeInterval = 1.0, handler: @escaping @Sendable (URL) -> Void) {
        self.repos = repos
        self.handler = handler
        guard !repos.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil,
            copyDescription: nil)
        let paths = repos.map { $0.appending(path: ".git").path } as CFArray
        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<GitDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            watcher.handle(Array(paths.prefix(count)))
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let stream = FSEventStreamCreate(
                nil, callback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency,
                flags)
        else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        queue.sync {}  // a callback already running must finish before this object goes away
        FSEventStreamRelease(stream)
    }

    /// A worktree added, removed, locked or moved: `.git/worktrees/<id>` itself or its `gitdir` / `locked` file.
    /// Not the HEAD, index and log files git rewrites on every commit inside a worktree.
    static func isWorktreeListChange(_ path: String) -> Bool {
        guard let range = path.range(of: "/.git/worktrees") else { return false }
        let rest = path[range.upperBound...].split(separator: "/")
        return rest.count <= 1 || (rest.count == 2 && (rest[1] == "gitdir" || rest[1] == "locked"))
    }

    private func handle(_ paths: [String]) {
        var changed = Set<String>()
        for path in paths where Self.isWorktreeListChange(path) {
            if let repo = repos.first(where: { PathIdentity.isInside(path, directory: $0.path) }) {
                changed.insert(repo.path)
            }
        }
        for repo in repos where changed.contains(repo.path) { handler(repo) }
    }
}
