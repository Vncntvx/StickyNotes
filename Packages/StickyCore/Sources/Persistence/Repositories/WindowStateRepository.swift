import Foundation
import GRDB
import Domain

// MARK: - WindowStateRepository (T051)
//
// Per tasks.md T051 and data-model.md §WindowState:
// - Per-note window geometry + display preferences.
// - Device-local ONLY — NEVER synchronized (constitution IV/IX).
// - `frame` is the preferred frame on the preferred display;
//   `fallbackFrame` is a temp frame when the preferred display is
//   disconnected (FR-035 / T054).
// - `isOpen` is the current open-window registry (one window per note).
// - Not restored after relaunch is a *behavior* (FR-007); the geometry is
//   still stored so a reopened note returns to its frame.

/// Repository for `WindowState` rows. Device-local; never syncs.
public final class SQLiteWindowStateRepository: Sendable {
    private let store: DatabaseStore
    private let encoder: CanonicalJSONEncoder
    private let decoder: CanonicalJSONDecoder

    public init(store: DatabaseStore) {
        self.store = store
        self.encoder = CanonicalJSONEncoder()
        self.decoder = CanonicalJSONDecoder()
    }

    // MARK: - Read

    /// Fetches the window state for a note. Returns `nil` if no row exists
    /// (the note has never been opened).
    public func fetch(noteId: UUID) async throws -> WindowState? {
        try await store.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM windowState WHERE noteId = ?",
                arguments: [noteId.uuidString]
            ) else { return nil }
            return try self.windowStateFromRow(row)
        }
    }

    // MARK: - Write

    /// Inserts or replaces the window state for a note. Called by the
    /// NoteWindowCoordinator when a window moves, resizes, or closes.
    public func upsert(_ state: WindowState) async throws {
        try await store.write { db in
            let frameData = try self.encoder.encode(state.frame)
            let frameJSON = String(data: frameData, encoding: .utf8) ?? "{}"
            let fallbackJSON: String?
            if let fallback = state.fallbackFrame {
                let data = try self.encoder.encode(fallback)
                fallbackJSON = String(data: data, encoding: .utf8) ?? "{}"
            } else {
                fallbackJSON = nil
            }
            try db.execute(
                sql: """
                    INSERT INTO windowState (noteId, frame, preferredDisplayUUID, fallbackFrame, isOpen, lastOpenedAt)
                    VALUES (?, ?, ?, ?, ?, ?)
                    ON CONFLICT(noteId) DO UPDATE SET
                        frame = excluded.frame,
                        preferredDisplayUUID = excluded.preferredDisplayUUID,
                        fallbackFrame = excluded.fallbackFrame,
                        isOpen = excluded.isOpen,
                        lastOpenedAt = excluded.lastOpenedAt
                    """,
                arguments: [
                    state.noteId.uuidString,
                    frameJSON,
                    state.preferredDisplayUUID,
                    fallbackJSON,
                    state.isOpen,
                    state.lastOpenedAt,
                ]
            )
        }
    }

    /// Updates just the frame + preferred display (e.g., the user dragged
    /// the window). Lighter than a full upsert.
    public func updateFrame(noteId: UUID, frame: WindowFrame, preferredDisplayUUID: String?) async throws {
        try await store.write { db in
            let frameData = try self.encoder.encode(frame)
            let frameJSON = String(data: frameData, encoding: .utf8) ?? "{}"
            try db.execute(
                sql: """
                    INSERT INTO windowState (noteId, frame, preferredDisplayUUID, fallbackFrame, isOpen, lastOpenedAt)
                    VALUES (?, ?, ?, NULL, 0, NULL)
                    ON CONFLICT(noteId) DO UPDATE SET
                        frame = excluded.frame,
                        preferredDisplayUUID = excluded.preferredDisplayUUID
                    """,
                arguments: [noteId.uuidString, frameJSON, preferredDisplayUUID]
            )
        }
    }

    /// Sets the open-window registry flag + lastOpenedAt. Called when a
    /// note window opens.
    public func markOpen(noteId: UUID) async throws {
        try await store.write { db in
            // Use a valid zero-frame JSON so fetch() can decode it.
            let zeroFrame = "{\"x\":0,\"y\":0,\"width\":0,\"height\":0}"
            try db.execute(
                sql: """
                    INSERT INTO windowState (noteId, frame, preferredDisplayUUID, fallbackFrame, isOpen, lastOpenedAt)
                    VALUES (?, ?, NULL, NULL, 1, ?)
                    ON CONFLICT(noteId) DO UPDATE SET
                        isOpen = 1,
                        lastOpenedAt = excluded.lastOpenedAt
                    """,
                arguments: [noteId.uuidString, zeroFrame, Date()]
            )
        }
    }

    /// Clears the open-window registry flag. Called when a note window
    /// closes (FR-007: the geometry is retained for the next open).
    public func markClosed(noteId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: "UPDATE windowState SET isOpen = 0 WHERE noteId = ?",
                arguments: [noteId.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private func windowStateFromRow(_ row: Row) throws -> WindowState {
        let frameString: String = row["frame"] ?? "{}"
        let frame = try decoder.decode(WindowFrame.self, from: Data(frameString.utf8))
        let fallbackFrame: WindowFrame?
        if let fallbackString: String = row["fallbackFrame"], !fallbackString.isEmpty {
            fallbackFrame = try decoder.decode(WindowFrame.self, from: Data(fallbackString.utf8))
        } else {
            fallbackFrame = nil
        }
        return WindowState(
            noteId: UUID(uuidString: row["noteId"] ?? "") ?? UUID(),
            frame: frame,
            preferredDisplayUUID: row["preferredDisplayUUID"],
            fallbackFrame: fallbackFrame,
            isOpen: row["isOpen"] ?? false,
            lastOpenedAt: row["lastOpenedAt"]
        )
    }
}
