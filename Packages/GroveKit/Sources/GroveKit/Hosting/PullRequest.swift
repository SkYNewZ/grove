import Foundation

public enum PullRequestState: Equatable, Sendable {
    case open, merged, closed
}

/// A pull request / merge request coming from this repo itself (never from a fork).
public struct PullRequest: Equatable, Sendable {
    public let url: URL
    public let state: PullRequestState
    /// Source branch name.
    public let branch: String
    /// Last commit of the source branch; lets a detached worktree find its request.
    public let headSHA: String?
    public let title: String?

    public init(
        url: URL, state: PullRequestState, branch: String, headSHA: String? = nil, title: String? = nil
    ) {
        self.url = url
        self.state = state
        self.branch = branch
        self.headSHA = headSHA
        self.title = title
    }

    /// `7` for `…/pull/7` and `…/-/merge_requests/7`.
    public var number: Int? { Int(url.lastPathComponent) }

    /// The request a worktree belongs to: matched by branch, else by `head` commit (a detached worktree has no
    /// branch). Preference open, then merged, then closed; within a state the first listed, i.e. the most
    /// recent, wins.
    /// shortcut: only the most recent requests are read (200 on GitHub, 100 on GitLab); older ones are
    /// not found, raise the limits if that bites.
    /// A merged or closed request only counts when it ended at this worktree's commit: a new branch that reuses
    /// an old branch name must not inherit its badge. The main worktree sits on a long-lived branch (develop,
    /// main), so only an open request counts there.
    public static func best(
        forBranch branch: String?, head: String?, isMain: Bool = false, in requests: [PullRequest]
    ) -> PullRequest? {
        func preferred(_ candidates: [PullRequest]) -> PullRequest? {
            for state in [PullRequestState.open, .merged, .closed] {
                if isMain && state != .open { continue }
                let found = candidates.first {
                    $0.state == state
                        && ($0.state == .open || head == nil || $0.headSHA == nil || $0.headSHA == head)
                }
                if let found { return found }
            }
            return nil
        }
        if let branch { return preferred(requests.filter { $0.branch == branch }) }
        // Only a detached worktree is matched by commit: a branch checkout (main after a fast-forward merge)
        // would otherwise show the badge of an unrelated request.
        guard let head else { return nil }
        return preferred(requests.filter { $0.headSHA == head })
    }
}
