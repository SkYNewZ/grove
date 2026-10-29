import AppKit
import CryptoKit
import Foundation

public enum ClaudeLaunchMode: String, CaseIterable, Sendable {
    /// `claude --continue` when the worktree already has a conversation, else a new one.
    case resumeLatest
    case newSession
}

public enum LaunchError: Error, Equatable, LocalizedError {
    case claudeMissing
    case terminalUnavailable

    public var errorDescription: String? {
        switch self {
        case .claudeMissing:
            "La commande `claude` est introuvable. Installe Claude Code ou vérifie ton PATH."
        case .terminalUnavailable:
            "Impossible d'ouvrir le terminal pour ce dossier."
        }
    }
}

/// How a terminal is driven so the user keeps their own setup (profile, theme, shell integration).
enum TerminalStrategy: Equatable {
    /// Warp opens a folder with a bare prompt, so it gets a `warp://` URL or a tab config instead.
    case warp
    /// Opening the folder with the app gives a new window/tab there; Claude goes through a `.command` script.
    case generic
}

/// Opens terminals, Claude Code and web pages. Terminal.app-like terminals open the folder itself; Claude Code
/// runs from a small `.command` script, except in Warp which gets a `warp://` URL and one tab config file.
/// shortcut: Claude Desktop has no deep link that opens a given folder (`claude://code/new` takes none), so
/// Claude Code always starts as the CLI.
public struct Launcher: Sendable {
    private let tools: ToolPaths
    private let scriptsDirectory: URL
    private let projectsDirectory: URL
    private let tabConfigsDirectory: URL

    public init(
        tools: ToolPaths,
        scriptsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: "Library/Application Support/Grove/launch"),
        projectsDirectory: URL = ClaudeSessions.defaultProjectsDirectory,
        tabConfigsDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()).appending(
            path: ".warp/tab_configs")
    ) {
        self.tools = tools
        self.scriptsDirectory = scriptsDirectory
        self.projectsDirectory = projectsDirectory
        self.tabConfigsDirectory = tabConfigsDirectory
    }

    public func openTerminal(at directory: URL) async throws {
        let terminal = DefaultTerminal.locate()
        switch Self.strategy(forBundleIdentifier: DefaultTerminal.bundleIdentifier(of: terminal)) {
        case .warp:
            guard let url = Self.warpTabURL(path: directory.path) else {
                throw LaunchError.terminalUnavailable
            }
            try await open(url, withApplicationAt: terminal)
        case .generic:
            try await open(directory, withApplicationAt: terminal)
        }
    }

    public func openClaude(at directory: URL, mode: ClaudeLaunchMode) async throws {
        guard let claude = tools.claude else { throw LaunchError.claudeMissing }
        let resume =
            mode == .resumeLatest
            && ClaudeSessions.hasSession(forDirectoryAt: directory.path, projectsDirectory: projectsDirectory)
        let command = Self.claudeCommand(claude: claude, resume: resume)
        let terminal = DefaultTerminal.locate()
        switch Self.strategy(forBundleIdentifier: DefaultTerminal.bundleIdentifier(of: terminal)) {
        case .warp:
            try writeClaudeTabConfig(directory: directory.path, command: command)
            try await open(Self.warpClaudeTabURL, withApplicationAt: terminal)
        case .generic:
            let script = try writeScript(named: "claude", directory: directory, command: "exec \(command)")
            try await open(script, withApplicationAt: terminal)
        }
    }

    // MARK: - Terminal strategy

    static func strategy(forBundleIdentifier bundleIdentifier: String?) -> TerminalStrategy {
        bundleIdentifier == "dev.warp.Warp-Stable" ? .warp : .generic
    }

    private func open(_ url: URL, withApplicationAt app: URL) async throws {
        try await NSWorkspace.shared.open(
            [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Warp

    // The force unwrap is on a constant literal URL, which always parses.
    static let warpClaudeTabURL = URL(string: "warp://tab_config/grove-claude")!

    /// `warp://action/new_tab?path=…` with the path percent-encoded (`&`, `=`, `#`, `+` included).
    static func warpTabURL(path: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        guard let encoded = path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "warp://action/new_tab?path=\(encoded)")
    }

    /// `"…"` as a TOML basic string: `\` and `"` are escaped, control characters too.
    static func tomlString(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{0}"..."\u{1F}", "\u{7F}": result += String(format: "\\u%04X", scalar.value)
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func tabConfig(directory: String, command: String) -> String {
        """
        name = \(tomlString("Grove · Claude Code"))

        [[panes]]
        id = "claude"
        type = "terminal"
        directory = \(tomlString(directory))
        commands = [\(tomlString(command))]
        is_focused = true

        [params]

        """
    }

    /// shortcut: one file rewritten at each launch, so Warp's + menu shows a single "Grove · Claude Code" entry and
    /// two launches in quick succession can race; upgrade to a file per worktree if that matters.
    @discardableResult
    func writeClaudeTabConfig(directory: String, command: String) throws -> URL {
        try FileManager.default.createDirectory(at: tabConfigsDirectory, withIntermediateDirectories: true)
        let file = tabConfigsDirectory.appending(path: "grove-claude.toml")
        try Self.tabConfig(directory: directory, command: command).write(
            to: file, atomically: true, encoding: .utf8)
        return file
    }

    // MARK: - Script

    static func claudeCommand(claude: String, resume: Bool) -> String {
        quoted(claude) + (resume ? " --continue" : "")
    }

    static func scriptContents(directory: String, command: String) -> String {
        "#!/bin/zsh -l\ncd -- \(quoted(directory)) || exit 1\n\(command)\n"
    }

    /// Single-quoted for the shell: `it's` becomes `'it'\''s'`.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    private func writeScript(named kind: String, directory: URL, command: String) throws -> URL {
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true)
        let digest = SHA256.hash(data: Data(directory.path.utf8)).prefix(6).map { String(format: "%02x", $0) }
        let script = scriptsDirectory.appending(path: "\(kind)-\(digest.joined()).command")
        try Self.scriptContents(directory: directory.path, command: command)
            .write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }
}
