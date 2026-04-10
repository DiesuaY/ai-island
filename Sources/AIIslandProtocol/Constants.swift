import Foundation

public enum AIIslandConstants {
    public static var socketDir: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.aiisland"
    }

    public static var socketPath: String {
        "\(socketDir)/island.sock"
    }

    public static let protocolVersion: Int = 1

    /// Path for the statusline cache file (context window + rate limits).
    public static var statusCachePath: String {
        "/tmp/aiisland-status.json"
    }

    public static let bridgeBinaryName: String = "aibridge"

    /// Marker string used to identify AI Island hooks in config files.
    public static let hookMarker: String = bridgeBinaryName

    /// Whether the process is running from inside a .app bundle.
    public static var isRunningFromAppBundle: Bool {
        Bundle.main.bundlePath.hasSuffix(".app")
    }

    /// Resolve the absolute path to the aibridge binary.
    ///
    /// Search order:
    /// 1. App bundle (Contents/MacOS/aibridge alongside the main executable)
    /// 2. Common install locations (/usr/local/bin, /opt/homebrew/bin, ~/.local/bin)
    /// 3. Fallback to bare name (relies on PATH)
    public static var aibridgePath: String {
        // 1. Check app bundle — aibridge lives next to the main executable
        if let execURL = Bundle.main.executableURL {
            let bundled = execURL.deletingLastPathComponent()
                .appendingPathComponent(bridgeBinaryName)
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled.path
            }
        }

        // 2. Common install locations
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/\(bridgeBinaryName)",
            "/opt/homebrew/bin/\(bridgeBinaryName)",
            "\(home)/.local/bin/\(bridgeBinaryName)",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // 3. Fallback — hope it is in PATH
        return bridgeBinaryName
    }
}
