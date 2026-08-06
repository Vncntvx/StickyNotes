import Foundation

// MARK: - Temp database path registry
//
// Tracks temp-database file paths created by `DatabaseStore.inMemory()` for
// tests. The OS cleans up the temp dir eventually, but tests can also force
// cleanup via `cleanupAll()`. Used by PersistenceTests to avoid leaving
// .sqlite/.wal/.shm files behind in CI.

public enum TempDatabasePaths {
    /// Use an actor to serialize access to the path list (Swift 6 strict
    /// concurrency — no nonisolated global mutable state).
    private actor Registry {
        private var paths: [String] = []

        func register(_ path: String) {
            paths.append(path)
        }

        func drainAll() -> [String] {
            let result = paths
            paths.removeAll()
            return result
        }
    }

    private static let registry = Registry()

    public static func register(_ path: String) async {
        await registry.register(path)
    }

    /// Removes all registered temp database files (and their -wal/-shm
    /// sidecars). Safe to call multiple times.
    public static func cleanupAll() async {
        let toRemove = await registry.drainAll()
        let fm = FileManager.default
        for path in toRemove {
            try? fm.removeItem(atPath: path)
            try? fm.removeItem(atPath: path + "-wal")
            try? fm.removeItem(atPath: path + "-shm")
        }
    }
}
