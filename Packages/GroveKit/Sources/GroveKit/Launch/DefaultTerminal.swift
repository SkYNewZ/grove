import AppKit
import UniformTypeIdentifiers

public enum DefaultTerminal {
    /// The app macOS runs shell scripts with (Terminal, iTerm, Warp, Ghostty... whatever the user chose),
    /// falling back to Warp, then Terminal.
    public static func locate() -> URL {
        let shell =
            LSCopyDefaultApplicationURLForContentType(
                UTType.unixExecutable.identifier as CFString, .shell, nil)?.takeRetainedValue() as URL?
        if let shell { return shell }
        if let warp = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "dev.warp.warp-stable") {
            return warp
        }
        return URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
    }

    public static func bundleIdentifier(of app: URL) -> String? {
        Bundle(url: app)?.bundleIdentifier
    }
}
