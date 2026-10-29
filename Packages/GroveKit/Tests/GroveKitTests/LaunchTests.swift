import Foundation
import Testing

@testable import GroveKit

struct LaunchTests {
    @Test func quotesPathsSafelyForTheShell() {
        #expect(Launcher.quoted("/a b/it's") == #"'/a b/it'\''s'"#)
        let script = Launcher.scriptContents(directory: "/x/Café's", command: "exec claude")
        #expect(script == "#!/bin/zsh -l\ncd -- '/x/Café'\\''s' || exit 1\nexec claude\n")
    }

    @Test func encodesProjectFolderNamesLikeClaudeCode() {
        #expect(ClaudeSessions.encode("/Users/q/src/demo/Café") == "-Users-q-src-demo-Caf-")
        #expect(
            ClaudeSessions.encode("/Users/q/app/.claude/worktrees/x-1")
                == "-Users-q-app--claude-worktrees-x-1")
    }

    @Test func detectsAnExistingConversation() throws {
        let fixture = try GitFixture()
        let projects = fixture.root.appending(path: "projects")
        let path = "/Users/q/src/Café"
        #expect(!ClaudeSessions.hasSession(forDirectoryAt: path, projectsDirectory: projects))

        let folder = projects.appending(path: "-Users-q-src-Caf-")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(!ClaudeSessions.hasSession(forDirectoryAt: path, projectsDirectory: projects))
        try "{}".write(to: folder.appending(path: "s.jsonl"), atomically: true, encoding: .utf8)
        #expect(ClaudeSessions.hasSession(forDirectoryAt: path, projectsDirectory: projects))
    }

    @Test func claudeNeedsAnInstalledBinary() async throws {
        let fixture = try GitFixture()
        let launcher = Launcher(tools: ToolPaths(), scriptsDirectory: fixture.root)
        await #expect(throws: LaunchError.claudeMissing) {
            try await launcher.openClaude(at: fixture.root, mode: .newSession)
        }
    }

    @Test func findsADefaultTerminalApp() {
        #expect(DefaultTerminal.locate().pathExtension == "app")
    }

    // MARK: - Terminal strategy

    @Test func strategyIsWarpOnlyForWarpBundle() {
        #expect(Launcher.strategy(forBundleIdentifier: "dev.warp.Warp-Stable") == .warp)
        #expect(Launcher.strategy(forBundleIdentifier: "com.apple.Terminal") == .generic)
        #expect(Launcher.strategy(forBundleIdentifier: "com.googlecode.iterm2") == .generic)
        #expect(Launcher.strategy(forBundleIdentifier: nil) == .generic)
    }

    @Test func readsTheBundleIdentifierOfTheChosenTerminal() {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        #expect(DefaultTerminal.bundleIdentifier(of: terminal) == "com.apple.Terminal")
        #expect(DefaultTerminal.bundleIdentifier(of: URL(fileURLWithPath: "/nonexistent.app")) == nil)
    }

    @Test func warpTabURLEncodesPathWithSpaces() {
        #expect(
            Launcher.warpTabURL(path: "/Users/q/My Repo")?.absoluteString
                == "warp://action/new_tab?path=/Users/q/My%20Repo")
    }

    @Test func warpTabURLEncodesQueryDelimitersAndNonASCII() {
        #expect(
            Launcher.warpTabURL(path: "/x/a&b=c+d#e?f/Café")?.absoluteString
                == "warp://action/new_tab?path=/x/a%26b%3Dc%2Bd%23e%3Ff/Caf%C3%A9")
    }

    // MARK: - Warp tab config

    @Test func tabConfigEscapesQuotesAndBackslashes() {
        #expect(Launcher.tomlString(#"a "b" \c"#) == #""a \"b\" \\c""#)
        #expect(Launcher.tomlString("line\nbreak\ttab\u{1}") == #""line\nbreak\ttab\u0001""#)

        let toml = Launcher.tabConfig(
            directory: #"/x/we"ird\dir with space/it's"#, command: "'/bin/claude' --continue")
        #expect(toml.contains(#"directory = "/x/we\"ird\\dir with space/it's""#))
        #expect(toml.contains(#"commands = ["'/bin/claude' --continue"]"#))
        #expect(toml.hasPrefix("name = \"Grove · Claude Code\"\n"))
        #expect(toml.contains("id = \"claude\"\ntype = \"terminal\""))
    }

    @Test func claudeCommandShellQuotesThePathAndAddsContinue() {
        #expect(
            Launcher.claudeCommand(claude: "/a b/it's/claude", resume: false) == #"'/a b/it'\''s/claude'"#)
        #expect(Launcher.claudeCommand(claude: "/bin/claude", resume: true) == "'/bin/claude' --continue")
    }

    @Test func writesOneOverwrittenTabConfigIntoTheInjectedDirectory() throws {
        let fixture = try GitFixture()
        let configs = fixture.root.appending(path: "tab_configs")
        let launcher = Launcher(tools: ToolPaths(), tabConfigsDirectory: configs)

        let first = try launcher.writeClaudeTabConfig(directory: "/x/one", command: "'/bin/claude'")
        let second = try launcher.writeClaudeTabConfig(
            directory: "/x/two", command: "'/bin/claude' --continue")

        #expect(first == second)
        #expect(first == configs.appending(path: "grove-claude.toml"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: configs.path) == ["grove-claude.toml"])
        let contents = try String(contentsOf: second, encoding: .utf8)
        #expect(contents.contains(#"directory = "/x/two""#))
        #expect(!contents.contains("/x/one"))
        #expect(Launcher.warpClaudeTabURL.absoluteString == "warp://tab_config/grove-claude")
    }
}
