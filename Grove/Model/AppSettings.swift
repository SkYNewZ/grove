import Foundation
import GroveKit
import Observation

/// User preferences, persisted in UserDefaults. Launch at login is not stored here: macOS owns that state.
@Observable
final class AppSettings {
    static let menuBarLimits = 5...10

    private let defaults: UserDefaults

    var scanRoots: [String] {
        didSet { defaults.set(scanRoots, forKey: Key.roots) }
    }
    var pinnedRepos: [String] {
        didSet { defaults.set(pinnedRepos, forKey: Key.pinned) }
    }
    var menuBarLimit: Int {
        didSet { defaults.set(menuBarLimit, forKey: Key.limit) }
    }
    var claudeMode: ClaudeLaunchMode {
        didSet { defaults.set(claudeMode.rawValue, forKey: Key.claudeMode) }
    }

    var explainModel: ExplainModel {
        didSet { defaults.set(explainModel.rawValue, forKey: Key.explainModel) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        scanRoots = defaults.stringArray(forKey: Key.roots) ?? []
        pinnedRepos = defaults.stringArray(forKey: Key.pinned) ?? []
        let limit = defaults.integer(forKey: Key.limit)
        menuBarLimit = Self.menuBarLimits.contains(limit) ? limit : 8
        claudeMode = defaults.string(forKey: Key.claudeMode).flatMap(ClaudeLaunchMode.init) ?? .resumeLatest
        explainModel = defaults.string(forKey: Key.explainModel).flatMap(ExplainModel.init) ?? .haiku
    }

    func togglePin(_ repoPath: String) {
        if let index = pinnedRepos.firstIndex(of: repoPath) {
            pinnedRepos.remove(at: index)
        } else {
            pinnedRepos.append(repoPath)
        }
    }

    private enum Key {
        static let roots = "scanRoots"
        static let pinned = "pinnedRepos"
        static let limit = "menuBarLimit"
        static let claudeMode = "claudeMode"
        static let explainModel = "explainModel"
    }
}
