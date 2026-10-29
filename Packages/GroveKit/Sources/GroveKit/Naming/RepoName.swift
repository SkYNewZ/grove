import Foundation

/// Display name of a repo: the README title when there is one, else the folder name.
public enum RepoName {
    public static func displayName(for repo: URL) -> String {
        let folder = repo.lastPathComponent.precomposedStringWithCanonicalMapping
        guard let readme = readmeURL(in: repo), let handle = try? FileHandle(forReadingFrom: readme),
            let head = try? handle.read(upToCount: 16 * 1024)
        else { return folder }
        return readmeTitle(String(decoding: head, as: UTF8.self)) ?? folder
    }

    /// First `# Title`, setext title or `<h1>` of a Markdown document, skipping front matter, comments and code fences.
    static func readmeTitle(_ markdown: String) -> String? {
        var lines = markdown.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }
            )
        {
            lines.removeSubrange(0...end)
        }
        var inFence = false
        var inComment = false
        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") { inFence.toggle() }
            if inFence { continue }
            if line.hasPrefix("<!--") { inComment = true }
            let wasComment = inComment
            if line.contains("-->") { inComment = false }
            if wasComment { continue }

            if line.hasPrefix("# "), let title = clean(String(line.dropFirst(2))) { return title }
            if let match = line.firstMatch(of: #/(?i)<h1[^>]*>(.*?)</h1>/#),
                let title = clean(String(match.1))
            {
                return title
            }
            if !line.isEmpty, index + 1 < lines.count,
                lines[index + 1].trimmingCharacters(in: .whitespaces).wholeMatch(of: #/=+/#) != nil,
                let title = clean(line)
            {
                return title
            }
        }
        return nil
    }

    private static func clean(_ text: String) -> String? {
        var result = text
        result = result.replacing(#/!\[[^\]]*\]\([^)]*\)/#, with: "")  // badges and images
        result = result.replacing(#/\[([^\]]*)\]\([^)]*\)/#) { String($0.1) }  // links keep their text
        result = result.replacing(#/<[^>]+>/#, with: "")
        result = result.replacing(#/[*`]/#, with: "")
        result = result.replacing(#/\s+#+$/#, with: "")  // closing hashes of "# Title #"
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func readmeURL(in repo: URL) -> URL? {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: repo.path)) ?? []
        let readmes = names.filter { $0.lowercased().hasPrefix("readme") }.sorted {
            (rank($0), $0) < (rank($1), $1)
        }
        return readmes.first.map { repo.appending(path: $0) }
    }

    /// Markdown first: `README.md` before `README.txt`.
    private static func rank(_ name: String) -> Int {
        let lowered = name.lowercased()
        return lowered.hasSuffix(".md") || lowered.hasSuffix(".markdown") ? 0 : 1
    }
}
