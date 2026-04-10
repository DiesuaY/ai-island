import Foundation

/// Shared shell utilities for resolving commands in the user's full PATH.
/// GUI apps have a narrower PATH than terminal sessions; these helpers
/// use a login shell to get the correct PATH.
enum ShellUtils {

    /// Resolve the absolute path of a command using the user's login shell PATH.
    /// Returns nil if the command is not found.
    static func which(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        // Pass command as a positional arg ($1) to avoid shell injection
        process.arguments = ["-l", "-c", "which -- \"$1\"", "zsh", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let path = output, !path.isEmpty {
                    return path
                }
            }
        } catch {}
        return nil
    }
}
