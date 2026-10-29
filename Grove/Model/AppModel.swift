import AppKit
import GroveKit
import Observation

struct RemovalReview: Identifiable {
    let id = UUID()
    let plan: RemovalPlan
    let repoName: String
}

enum ExplainState {
    case running
    case done(Explanation)
    case failed(String)
}

struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Everything the windows and the menu bar show. Git answers arrive first (fast); sizes and PR/MR links
/// fill in afterwards.
@Observable
final class AppModel {
    let settings: AppSettings

    private(set) var snapshots: [RepoSnapshot] = []
    private(set) var sizes: [String: RepoSizes] = [:]
    /// repo id → every PR/MR read from the forge (open, merged and closed).
    private(set) var pullRequests: [String: [PullRequest]] = [:]
    private(set) var pullRequestProblems: [String: String] = [:]
    private(set) var isLoading = false
    private(set) var tools = ToolPaths()
    private(set) var busyWorktrees: Set<String> = []
    /// "worktree path@HEAD" → state: a new commit makes the previous explanation stale.
    private(set) var explanations: [String: ExplainState] = [:]
    var removal: RemovalReview?
    var notice: Notice?

    private var git = GitClient()
    private var hosts = ForgeHosts()
    private var watcher: GitDirectoryWatcher?
    private var detailsTasks: [String: Task<Void, Never>] = [:]
    private var lastReload: Date?
    private var watchedRepos: Set<String> = []
    private var started = false

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        tools = await ToolLocator.locate()
        git = GitClient(gitPath: tools.git ?? "/usr/bin/git")
        hosts = await ForgeHosts.discover(tools: tools)
        await reload()
    }

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let roots = settings.scanRoots.map { URL(fileURLWithPath: $0) }
        let loaded = await RepoLoader.load(
            roots: roots, git: git, gitlabHosts: hosts.gitlab, githubHosts: hosts.github)
        if loaded != snapshots { snapshots = loaded }  // an identical result must not redraw every row
        lastReload = Date()
        watch()
        refreshDetails(for: snapshots)
    }

    /// For app activation: skip when the last full reload is recent (the watcher covers worktree changes).
    func reloadIfStale() async {
        if let last = lastReload, Date().timeIntervalSince(last) < 30 { return }
        await reload()
    }

    func reloadRepo(at url: URL) async {
        let fresh = await RepoLoader.snapshot(
            of: url, git: git, gitlabHosts: hosts.gitlab, githubHosts: hosts.github)
        if let index = snapshots.firstIndex(where: { $0.id == fresh.id }) {
            if snapshots[index] != fresh { snapshots[index] = fresh }
        } else {
            snapshots.append(fresh)
        }
        refreshDetails(for: [fresh])
    }

    private func watch() {
        let repos = Set(snapshots.map(\.id))
        guard repos != watchedRepos else { return }
        watchedRepos = repos
        watcher = GitDirectoryWatcher(repos: snapshots.map(\.url)) { [weak self] repo in
            Task { @MainActor in await self?.reloadRepo(at: repo) }
        }
    }

    /// One task per repo, so reloading one repo never cancels the numbers still arriving for the others.
    private func refreshDetails(for repos: [RepoSnapshot]) {
        let pullRequestResolver = PullRequestResolver(tools: tools)
        for repo in repos {
            detailsTasks[repo.id]?.cancel()
            detailsTasks[repo.id] = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        let measured = await DiskUsage.measure(repo.entries.map(\.worktree))
                        guard !Task.isCancelled else { return }  // a newer refresh owns the numbers now
                        await self.store(sizes: measured, for: repo.id)
                    }
                    guard let remote = repo.remote, remote.forge != nil else { return }
                    group.addTask {
                        do {
                            let found = try await pullRequestResolver.requests(for: remote, in: repo.url)
                            guard !Task.isCancelled else { return }
                            await self.store(pullRequests: found, for: repo.id)
                        } catch {
                            await self.store(problem: error.localizedDescription, for: repo.id)
                        }
                    }
                }
            }
        }
    }

    private func store(sizes measured: RepoSizes, for id: String) {
        sizes[id] = measured
    }

    private func store(pullRequests found: [PullRequest], for id: String) {
        pullRequests[id] = found
        pullRequestProblems[id] = nil
    }

    private func store(problem: String, for id: String) {
        pullRequestProblems[id] = problem
    }

    // MARK: - Reading

    /// Pinned repos first, then by name.
    var sidebarRepos: [RepoSnapshot] {
        snapshots.sorted {
            let (a, b) = (settings.pinnedRepos.contains($0.id), settings.pinnedRepos.contains($1.id))
            return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Pinned repos, then the most recently active, up to the user's limit.
    var menuBarRepos: [RepoSnapshot] {
        let pinned = settings.pinnedRepos.compactMap { id in snapshots.first { $0.id == id } }
        let others = snapshots.filter { !settings.pinnedRepos.contains($0.id) }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        return Array((pinned + others).prefix(settings.menuBarLimit))
    }

    func totalSize(of repo: RepoSnapshot) -> Int64? { sizes[repo.id]?.total }

    func size(of entry: WorktreeEntry, in repo: RepoSnapshot) -> Int64? {
        sizes[repo.id]?.perWorktree[entry.worktree.path]
    }

    /// The best PR/MR of the worktree (open, else merged, else closed), matched by branch or by HEAD.
    private func bestRequest(for entry: WorktreeEntry, in repo: RepoSnapshot) -> PullRequest? {
        PullRequest.best(
            forBranch: entry.worktree.branch, head: entry.worktree.head, isMain: entry.worktree.isMain,
            in: pullRequests[repo.id] ?? [])
    }

    /// The worktree's PR/MR when there is one, else the repo's web page (`request` is nil then).
    func webTarget(for entry: WorktreeEntry, in repo: RepoSnapshot) -> (url: URL, request: PullRequest?)? {
        if let request = bestRequest(for: entry, in: repo) { return (request.url, request) }
        return repo.remote?.webURL.map { ($0, nil) }
    }

    // MARK: - Actions

    func openTerminal(at path: String) {
        perform { try await Launcher(tools: self.tools).openTerminal(at: URL(fileURLWithPath: path)) }
    }

    func openClaude(at path: String) {
        perform {
            try await Launcher(tools: self.tools).openClaude(
                at: URL(fileURLWithPath: path), mode: self.settings.claudeMode)
        }
    }

    private static func explainKey(_ entry: WorktreeEntry) -> String {
        "\(entry.id)@\(entry.worktree.head ?? "")"
    }

    func explanation(for entry: WorktreeEntry) -> ExplainState? { explanations[Self.explainKey(entry)] }

    /// Runs the explain call once per worktree state; `force` asks again.
    func explain(_ entry: WorktreeEntry, in repo: RepoSnapshot, force: Bool = false) {
        let key = Self.explainKey(entry)
        if !force, explanations[key] != nil { return }
        explanations[key] = .running
        let explainer = WorktreeExplainer(tools: tools, git: git)
        let model = settings.explainModel
        let request = bestRequest(for: entry, in: repo)
        Task {
            do {
                let base = try await git.defaultBase(of: repo.url)
                let result = try await explainer.explain(
                    entry, repoName: repo.name, repo: repo.url, base: base,
                    request: request, remote: repo.remote, model: model)
                explanations[key] = .done(result)
            } catch {
                explanations[key] = .failed(error.localizedDescription)
            }
        }
    }

    func openWeb(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func beginRemoval(_ entry: WorktreeEntry, in repo: RepoSnapshot) {
        busyWorktrees.insert(entry.id)
        Task {
            defer { busyWorktrees.remove(entry.id) }
            do {
                let plan = try await SafeRemover(git: git).plan(for: entry.worktree, in: repo.url)
                removal = RemovalReview(plan: plan, repoName: repo.name)
            } catch {
                notice = Notice(title: "Suppression impossible", message: error.localizedDescription)
            }
        }
    }

    func confirmRemoval(strong: Bool) {
        guard let review = removal else { return }
        busyWorktrees.insert(review.plan.worktree.path)
        Task {
            defer { busyWorktrees.remove(review.plan.worktree.path) }
            do {
                let result = try await SafeRemover(git: git).remove(review.plan, strongConfirmed: strong)
                removal = nil
                notice = Notice(title: "Worktree supprimé", message: Self.summary(of: result))
                await reloadRepo(at: review.plan.repo)
            } catch {
                removal = nil
                notice = Notice(title: "Suppression interrompue", message: error.localizedDescription)
            }
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task {
            do { try await action() } catch {
                notice = Notice(title: "Action impossible", message: error.localizedDescription)
            }
        }
    }

    private static func summary(of result: RemovalResult) -> String {
        var lines = ["Le dossier est dans la Corbeille."]
        lines.append("Sauvegarde git : \(result.backupRefs.joined(separator: ", "))")
        if let branch = result.branch {
            if let note = result.branchNote {
                lines.append("La branche « \(branch) » est conservée : \(note)")
            } else {
                lines.append("La branche locale « \(branch) » a été supprimée.")
            }
        }
        if !result.alsoPruned.isEmpty {
            lines.append(
                "Aussi oubliés par git (dossier déjà absent, sauvegardés) : \(result.alsoPruned.joined(separator: ", "))"
            )
        }
        return lines.joined(separator: "\n")
    }
}
