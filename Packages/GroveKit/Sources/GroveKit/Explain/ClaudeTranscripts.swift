import Foundation

/// Condensed view of a Claude Code conversation: how it started and how it ended.
public struct TranscriptDigest: Equatable, Sendable {
    public let file: String
    public let modified: Date
    public let firstRequest: String
    public let lastTurns: [String]
}

public enum ClaudeTranscripts {
    /// The most recent conversations Claude Code stored for `directory`, newest first.
    public static func recent(
        forDirectoryAt path: String, limit: Int = 5,
        projectsDirectory: URL = ClaudeSessions.defaultProjectsDirectory
    ) async -> [TranscriptDigest] {
        let folder = projectsDirectory.appending(path: ClaudeSessions.encode(path))
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files =
            (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        let newest = files.filter { $0.pathExtension == "jsonl" }
            .compactMap { url in
                (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate).map { (url, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
        var digests: [TranscriptDigest] = []
        for (url, modified) in newest {
            if let digest = await digest(of: url, modified: modified) { digests.append(digest) }
        }
        return digests
    }

    static func digest(of file: URL, modified: Date, keepTurns: Int = 6, maxCharacters: Int = 500) async
        -> TranscriptDigest?
    {
        var first: String?
        var last: [String] = []
        do {
            for try await line in file.lines {
                // Cheap filter before decoding: tool results and bookkeeping lines are most of a transcript.
                guard line.contains("\"type\":\"user\"") || line.contains("\"type\":\"assistant\"") else {
                    continue
                }
                guard let turn = turn(from: line) else { continue }
                let text = String(turn.text.prefix(maxCharacters))
                if first == nil, turn.role == "user" { first = text }
                last.append("\(turn.role == "user" ? "Utilisateur" : "Claude") : \(text)")
                if last.count > keepTurns { last.removeFirst() }
            }
        } catch { return nil }
        guard let first else { return nil }
        return TranscriptDigest(
            file: file.lastPathComponent, modified: modified, firstRequest: first, lastTurns: last)
    }

    /// Plain text turns only: skips tool calls, tool results, hook/system reminders and meta lines.
    static func turn(from line: String) -> (role: String, text: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
            let role = object["type"] as? String, role == "user" || role == "assistant",
            object["isMeta"] as? Bool != true,
            let message = object["message"] as? [String: Any]
        else { return nil }
        var parts: [String] = []
        if let text = message["content"] as? String {
            parts = [text]
        } else if let blocks = message["content"] as? [[String: Any]] {
            parts = blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        }
        let text = parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.hasPrefix("<") else { return nil }
        return (role, text)
    }
}
