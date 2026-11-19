import Foundation

/// Finds programs, including ones Homebrew installs when `PATH` lacks Homebrew's folder
/// (a terminal tab or a menu-bar app may start that way).
public enum ToolFinder {
    public static let extraFolders = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// The full path of `name`: each folder of `path` in order, then `extraFolders`.
    /// A name that already contains a `/` is checked as it stands.
    public static func find(_ name: String,
                            path: String? = ProcessInfo.processInfo.environment["PATH"],
                            isExecutable: (String) -> Bool = FileManager.default.isExecutableFile(atPath:)) -> String? {
        if name.isEmpty { return nil }
        if name.contains("/") { return isExecutable(name) ? name : nil }
        var folders = (path ?? "").split(separator: ":").map(String.init)
        for extra in extraFolders where !folders.contains(extra) { folders.append(extra) }
        for folder in folders {
            let candidate = folder.hasSuffix("/") ? folder + name : folder + "/" + name
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }
}
