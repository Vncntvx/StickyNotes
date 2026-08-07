import Foundation

// MARK: - AppGroupContainer (verified 2026-08-07)
//
// Deterministic App Group container resolution for the main app and the
// widget extension.
//
// `FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` is
// BROKEN on macOS 27 beta for ad-hoc-signed ("Sign to Run Locally") apps:
// it returns a path the sandbox profile denies write access to, while the
// deterministic `<home>/Library/Group Containers/<group-id>/` path IS
// granted by the app-groups sandbox profile (verified with a sandboxed
// probe binary 2026-08-07). The container path is therefore computed
// directly instead of resolved through containermanagerd.

/// Resolves the App Group container directory for a group identifier.
public enum AppGroupContainer {
    /// The group container URL, creating the directory chain when missing.
    /// Returns `nil` only when the user's home directory is unavailable.
    public static func url(for groupIdentifier: String) -> URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Group Containers", isDirectory: true)
            .appendingPathComponent(groupIdentifier, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
