import Foundation

/// `/private/var/x` and `/var/x` are the same place on macOS, and git, lsof and FileManager disagree on
/// which one they print. Compare paths through this, never with `==`.
enum PathIdentity {
    static func canonical(_ path: String) -> String {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        return standardized.hasPrefix("/private/")
            ? String(standardized.dropFirst("/private".count)) : standardized
    }

    static func same(_ a: String, _ b: String) -> Bool { canonical(a) == canonical(b) }

    static func isInside(_ path: String, directory: String) -> Bool {
        let path = canonical(path)
        let root = canonical(directory)
        return path == root || path.hasPrefix(root + "/")
    }
}
