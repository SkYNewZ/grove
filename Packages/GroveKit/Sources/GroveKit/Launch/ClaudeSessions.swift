import Foundation

/// Claude Code keeps a worktree's conversations in `~/.claude/projects/<path with every non-alphanumeric as ->`.
public enum ClaudeSessions {
    public static var defaultProjectsDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".claude/projects")
    }

    /// True when Claude Code already has at least one conversation for this working directory, so
    /// `claude --continue` has something to continue.
    public static func hasSession(
        forDirectoryAt path: String, projectsDirectory: URL = defaultProjectsDirectory
    ) -> Bool {
        // The folder name may be stored composed (é) or decomposed (e + ´): try both.
        let spellings = [
            path.precomposedStringWithCanonicalMapping, path.decomposedStringWithCanonicalMapping,
        ]
        return spellings.contains { spelling in
            let directory = projectsDirectory.appending(path: encode(spelling))
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
            return files.contains { $0.hasSuffix(".jsonl") }
        }
    }

    static func encode(_ path: String) -> String {
        String(
            path.unicodeScalars.map {
                ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) ? Character($0) : "-"
            })
    }
}
