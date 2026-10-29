import Foundation

@testable import GroveKit

/// Throwaway git repos in a temp directory, isolated from the user's git config.
final class GitFixture {
    static let environment = [
        "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_SYSTEM": "/dev/null",
        "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
    ]

    let root: URL
    var client: GitClient { GitClient(environment: Self.environment) }

    init() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
        root = base.appending(path: "grove-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    // Sync on purpose: test setup stays free of `await`.
    @discardableResult
    func git(_ arguments: String..., in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = ProcessInfo.processInfo.environment.merging(Self.environment) { $1 }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitError(arguments: arguments, status: process.terminationStatus, stderr: text)
        }
        return text
    }

    func commit(_ message: String, in directory: URL) throws {
        try git("commit", "-q", "--allow-empty", "-m", message, in: directory)
    }

    /// A main repo `name` on `main` with one commit, pushed to a bare `origin` whose HEAD is `main`.
    /// Creates missing parent directories.
    func makeRepo(_ name: String, in parent: URL? = nil) throws -> URL {
        let parent = parent ?? root
        let origin = parent.appending(path: "\(name)-origin.git")
        let repo = parent.appending(path: name)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try git("init", "-q", "--bare", "-b", "main", origin.path, in: parent)
        try git("init", "-q", "-b", "main", in: repo)
        try commit("init", in: repo)
        try git("remote", "add", "origin", origin.path, in: repo)
        try git("push", "-q", "origin", "main", in: repo)
        try git("remote", "set-head", "origin", "main", in: repo)
        return repo
    }

    @discardableResult
    func addWorktree(_ name: String, branch: String? = nil, of repo: URL) throws -> URL {
        let directory = root.appending(path: name)
        if let branch {
            try git("worktree", "add", "-q", "-b", branch, directory.path, "main", in: repo)
        } else {
            try git("worktree", "add", "-q", "--detach", directory.path, "main", in: repo)
        }
        return directory
    }
}
