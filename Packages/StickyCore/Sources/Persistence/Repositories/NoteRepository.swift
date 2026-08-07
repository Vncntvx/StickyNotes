import Foundation
import GRDB
import Domain

// MARK: - SQLiteNoteRepository (T030)
//
// Per tasks.md T030: "Implement SQLite repository for Note + Block (CRUD,
// ordering) in `Packages/StickyCore/Sources/Persistence/Repositories/
// NoteRepository.swift`."
//
// Concrete SQLite-backed implementation of the `NoteRepository` and
// `BlockRepository` protocols from RepositoryProtocols.swift. Returns Sendable
// Domain snapshots; concrete GRDB rows are NOT exported (plan §Module
// boundaries).
//
// Maintains the FTS5 `note_fts_content` row transactionally on note changes
// so the search index stays in sync (T020/T042).
//
// Constitution VIII: every mutation advances version lineage (new versionId,
// parentVersionId = prior versionId, modifiedAt updated). Constitution IV:
// device-local fields are kept out of canonical JSON (handled by
// CanonicalCoding; here we persist rows directly).

/// Concrete SQLite-backed Note + Block repository.
public final class SQLiteNoteRepository: NoteRepository, BlockRepository, Sendable {
    private let store: DatabaseStore
    private let fullTextSearch: FullTextSearch
    private let canonicalEncoder: CanonicalJSONEncoder
    private let canonicalDecoder: CanonicalJSONDecoder

    public init(store: DatabaseStore, fullTextSearch: FullTextSearch) {
        self.store = store
        self.fullTextSearch = fullTextSearch
        self.canonicalEncoder = CanonicalJSONEncoder()
        self.canonicalDecoder = CanonicalJSONDecoder()
    }

    // MARK: - NoteRepository

    public func create(_ note: Note) async throws {
        try await store.write { db in
            try self.insertNoteRow(db, note: note)
            // Seed an empty FTS content row so the note is searchable by
            // title immediately; the SearchService (T042) refreshes the
            // full document when blocks change.
            try self.upsertSearchRow(
                db,
                noteId: note.id,
                title: note.title ?? "",
                body: "", summary: "", todos: "", code: "",
                fileNames: "", captions: "", ocr: ""
            )
        }
    }

    public func fetch(id: UUID) async throws -> Note? {
        try await store.read { db in
            try self.fetchNoteRow(db, id: id)
        }
    }

    public func fetchAll(lifecycle: NoteLifecycleState, sort: NoteSortKey) async throws -> [Note] {
        try await store.read { db in
            let orderClause: String
            switch sort {
            case .modified: orderClause = "modifiedAt DESC"
            case .created:  orderClause = "createdAt DESC"
            case .title:    orderClause = "title IS NULL, title ASC"
            case .manual:   orderClause = "manualSortKey ASC"
            }
            let sql = """
                SELECT * FROM note
                WHERE lifecycleState = ?
                ORDER BY \(orderClause)
                """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [lifecycle.rawValue])
            return rows.compactMap { try? self.noteFromRow($0) }
        }
    }

    public func update(_ note: Note, modifyingDeviceId: UUID) async throws {
        try await store.write { db in
            // Bump version lineage: parentVersionId ← prior versionId;
            // new versionId; modifiedAt ← now.
            var bumped = note
            let priorVersionId = note.versionId
            bumped.versionId = UUID()
            bumped.parentVersionId = priorVersionId
            bumped.lastModifiedDeviceId = modifyingDeviceId
            bumped.modifiedAt = Date()
            try self.updateNoteRow(db, note: bumped)
            // Refresh FTS title in case the user changed it.
            try self.upsertSearchRow(
                db,
                noteId: bumped.id,
                title: bumped.title ?? "",
                body: "", summary: "", todos: "", code: "",
                fileNames: "", captions: "", ocr: ""
            )
        }
    }

    public func trash(id: UUID, deviceId: UUID) async throws {
        try await store.write { db in
            let now = Date()
            try db.execute(
                sql: """
                    UPDATE note
                    SET lifecycleState = 'trashed',
                        trashedAt = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [now, UUID().uuidString, id.uuidString, deviceId.uuidString, now, id.uuidString]
            )
        }
    }

    public func restore(id: UUID, deviceId: UUID) async throws {
        try await store.write { db in
            let now = Date()
            // FR-022a (clarified 2026-08-07): on restore, reset
            // manualSortKey to (max active sort-key) + 1024, placing the
            // restored note at the end of Manual order. The pre-deletion
            // sort-key is NOT retained (notes may have been inserted or
            // reordered during the note's absence). The new key is strictly
            // greater than all existing keys, so restore alone never
            // triggers renormalization.
            let maxSortKey: Int = try Int.fetchOne(
                db,
                sql: "SELECT MAX(manualSortKey) FROM note WHERE lifecycleState = 'active'",
                arguments: []
            ) ?? ManualSortKeys.initialSortKey - ManualSortKeys.standardGap
            let restoredSortKey = maxSortKey + ManualSortKeys.standardGap
            try db.execute(
                sql: """
                    UPDATE note
                    SET lifecycleState = 'active',
                        trashedAt = NULL,
                        manualSortKey = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [restoredSortKey, UUID().uuidString, id.uuidString, deviceId.uuidString, now, id.uuidString]
            )
        }
    }

    public func permanentlyDelete(id: UUID, deviceId: UUID) async throws {
        try await store.write { db in
            // Fetch the current versionId to record in the tombstone: the
            // tombstone MUST carry the note's actual version lineage so a
            // remote device can decide honor-vs-recover (data-model.md
            // §Tombstone lifecycle; T163l delete-vs-edit).
            let currentVersionId: String? = try String.fetchOne(
                db,
                sql: "SELECT versionId FROM note WHERE id = ?",
                arguments: [id.uuidString]
            )
            let parentVersionId: String? = try String.fetchOne(
                db,
                sql: "SELECT parentVersionId FROM note WHERE id = ?",
                arguments: [id.uuidString]
            )
            let deletedVersionId = UUID(uuidString: currentVersionId ?? "") ?? UUID()

            // Insert the tombstone (sync-safety retention; data-model.md
            // §Tombstone). canPurgeRemote defaults to false — the sync
            // engine flips it once all known devices have seen the deletion.
            try db.execute(
                sql: """
                    INSERT INTO tombstone (noteId, deletedVersionId, parentVersionId, deletingDeviceId, deletedAt, canPurgeRemote)
                    VALUES (?, ?, ?, ?, ?, 0)
                    ON CONFLICT(noteId) DO UPDATE SET
                        deletedVersionId = excluded.deletedVersionId,
                        parentVersionId = excluded.parentVersionId,
                        deletingDeviceId = excluded.deletingDeviceId,
                        deletedAt = excluded.deletedAt
                    """,
                arguments: [id.uuidString, deletedVersionId.uuidString, parentVersionId, deviceId.uuidString, Date()]
            )

            // Mark the note as permanently deleted. Readable content (blocks,
            // etc.) is removed by a separate purge step (T079/T128) when sync
            // safety allows; the row stays for tombstone linkage.
            try db.execute(
                sql: """
                    UPDATE note
                    SET lifecycleState = 'permanentlyDeleted',
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [UUID().uuidString, id.uuidString, deviceId.uuidString, Date(), id.uuidString]
            )
        }
    }

    public func updateSortKey(id: UUID, sortKey: Int, deviceId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    UPDATE note
                    SET manualSortKey = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [sortKey, UUID().uuidString, id.uuidString, deviceId.uuidString, Date(), id.uuidString]
            )
        }
    }

    // MARK: - Empty Trash (FR-014b, T231)

    public func emptyTrash(deviceId: UUID) async throws -> [UUID] {
        try await store.write { db in
            let now = Date()
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id FROM note WHERE lifecycleState = 'trashed'"
            )
            let ids = rows.compactMap { UUID(uuidString: $0["id"] ?? "") }
            for id in ids {
                // Same permanent-deletion path as `permanentlyDelete`:
                // tombstone retained for sync-safety (FR-174); readable
                // content removal is a later purge step. The tombstone
                // carries the note's actual version lineage.
                let currentVersionId: String? = try String.fetchOne(
                    db,
                    sql: "SELECT versionId FROM note WHERE id = ?",
                    arguments: [id.uuidString]
                )
                let parentVersionId: String? = try String.fetchOne(
                    db,
                    sql: "SELECT parentVersionId FROM note WHERE id = ?",
                    arguments: [id.uuidString]
                )
                try db.execute(
                    sql: """
                        INSERT INTO tombstone (noteId, deletedVersionId, parentVersionId, deletingDeviceId, deletedAt, canPurgeRemote)
                        VALUES (?, ?, ?, ?, ?, 0)
                        ON CONFLICT(noteId) DO UPDATE SET
                            deletedVersionId = excluded.deletedVersionId,
                            parentVersionId = excluded.parentVersionId,
                            deletingDeviceId = excluded.deletingDeviceId,
                            deletedAt = excluded.deletedAt
                        """,
                    arguments: [id.uuidString, currentVersionId ?? UUID().uuidString, parentVersionId, deviceId.uuidString, now]
                )
                try db.execute(
                    sql: """
                        UPDATE note
                        SET lifecycleState = 'permanentlyDeleted',
                            trashedAt = NULL,
                            versionId = ?,
                            parentVersionId = (SELECT versionId FROM note WHERE id = ?),
                            lastModifiedDeviceId = ?,
                            modifiedAt = ?
                        WHERE id = ?
                        """,
                    arguments: [UUID().uuidString, id.uuidString, deviceId.uuidString, now, id.uuidString]
                )
            }
            return ids
        }
    }

    // MARK: - Scale limits (FR-090b, T236)

    public func validateNoteContentSize(noteId: UUID) async throws {
        let encoder = canonicalEncoder
        try await store.read { db in
            let byteCount = try Self.noteContentByteCount(db, noteId: noteId, encoder: encoder)
            if ScaleLimits.noteContentError(byteCount: byteCount) != nil {
                throw StickyError.persistence(.contentTooLarge)
            }
        }
    }

    /// Computes the canonical envelope byte size for a note (note + blocks,
    /// before asset payloads). Used by `validateNoteContentSize`.
    static func noteContentByteCount(
        _ db: Database,
        noteId: UUID,
        encoder: CanonicalJSONEncoder
    ) throws -> Int {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM note WHERE id = ?",
                                         arguments: [noteId.uuidString]) else { return 0 }
        let note = Note(
            id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
            title: row["title"],
            colorKey: NoteColorKey(rawValue: row["colorKey"] ?? "") ?? .yellow,
            customColor: row["customColor"],
            transparency: row["transparency"] ?? 1.0,
            textSize: row["textSize"] ?? 13,
            alwaysOnTop: row["alwaysOnTop"] ?? false,
            widgetEligible: row["widgetEligible"] ?? true,
            coverScreenshotBlockId: (row["coverScreenshotBlockId"] as String?).flatMap { UUID(uuidString: $0) },
            manualSortKey: row["manualSortKey"] ?? 0,
            lifecycleState: NoteLifecycleState(rawValue: row["lifecycleState"] ?? "") ?? .active,
            trashedAt: row["trashedAt"],
            conflictOriginNoteId: (row["conflictOriginNoteId"] as String?).flatMap { UUID(uuidString: $0) },
            conflictLabel: row["conflictLabel"],
            versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
            parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
            lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
            createdAt: row["createdAt"] ?? Date(),
            modifiedAt: row["modifiedAt"] ?? Date()
        )
        let blockRows = try Row.fetchAll(
            db,
            sql: "SELECT * FROM block WHERE noteId = ? ORDER BY sortKey ASC",
            arguments: [noteId.uuidString]
        )
        var blocks: [Block] = []
        for row in blockRows {
            guard let payloadString: String = row["payload"],
                  let data = payloadString.data(using: .utf8),
                  let payload = try? CanonicalJSONDecoder().decode(CanonicalBlockPayload.self, from: data) else { continue }
            blocks.append(
                Block(
                    id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
                    noteId: noteId,
                    kind: BlockKind(rawValue: row["kind"] ?? "") ?? .richText,
                    sortKey: row["sortKey"] ?? 0,
                    payload: payload,
                    versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
                    parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
                    lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
                    createdAt: row["createdAt"] ?? Date(),
                    modifiedAt: row["modifiedAt"] ?? Date()
                )
            )
        }
        let document = CanonicalNote(note: note, blocks: blocks)
        return try encoder.encode(document).count
    }

    // MARK: - BlockRepository

    public func fetchBlocks(noteId: UUID) async throws -> [Block] {
        try await store.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT * FROM block WHERE noteId = ? ORDER BY sortKey ASC",
                arguments: [noteId.uuidString]
            )
            return rows.compactMap { try? self.blockFromRow($0) }
        }
    }

    public func insert(_ block: Block) async throws {
        try await insertBlock(block)
    }

    public func insertBlock(_ block: Block) async throws {
        try await store.write { db in
            try self.insertBlockRow(db, block: block)
            // FR-090b (T236): the 5 MB structured-content cap is enforced at
            // the persistence boundary — an oversize content change is
            // refused within the same transaction (rollback preserves the
            // last valid saved state).
            let byteCount = try Self.noteContentByteCount(db, noteId: block.noteId, encoder: self.canonicalEncoder)
            if ScaleLimits.noteContentError(byteCount: byteCount) != nil {
                throw StickyError.persistence(.contentTooLarge)
            }
        }
    }

    public func update(_ block: Block, modifyingDeviceId: UUID) async throws {
        try await updateBlock(block, modifyingDeviceId: modifyingDeviceId)
    }

    public func updateBlock(_ block: Block, modifyingDeviceId: UUID) async throws {
        try await store.write { db in
            var bumped = block
            let priorVersionId = block.versionId
            bumped.versionId = UUID()
            bumped.parentVersionId = priorVersionId
            bumped.lastModifiedDeviceId = modifyingDeviceId
            bumped.modifiedAt = Date()
            try self.updateBlockRow(db, block: bumped)
            // FR-090b (T236): same cap as insert — refused, state preserved.
            let byteCount = try Self.noteContentByteCount(db, noteId: block.noteId, encoder: self.canonicalEncoder)
            if ScaleLimits.noteContentError(byteCount: byteCount) != nil {
                throw StickyError.persistence(.contentTooLarge)
            }
        }
    }

    public func delete(id: UUID) async throws {
        try await deleteBlock(id: id)
    }

    public func deleteBlock(id: UUID) async throws {
        try await store.write { db in
            // App-enforced FK nulling: if this block was a note's cover
            // screenshot, clear the reference (m0001_initial.swift comment).
            try db.execute(
                sql: "UPDATE note SET coverScreenshotBlockId = NULL WHERE coverScreenshotBlockId = ?",
                arguments: [id.uuidString]
            )
            try db.execute(
                sql: "DELETE FROM block WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    public func reorder(blockId: UUID, newSortKey: Int, deviceId: UUID) async throws {
        try await store.write { db in
            try db.execute(
                sql: """
                    UPDATE block
                    SET sortKey = ?,
                        versionId = ?,
                        parentVersionId = (SELECT versionId FROM block WHERE id = ?),
                        lastModifiedDeviceId = ?,
                        modifiedAt = ?
                    WHERE id = ?
                    """,
                arguments: [newSortKey, UUID().uuidString, blockId.uuidString, deviceId.uuidString, Date(), blockId.uuidString]
            )
        }
    }

    // MARK: - Row mapping

    private func insertNoteRow(_ db: Database, note: Note) throws {
        try db.execute(
            sql: """
                INSERT INTO note (
                    id, title, colorKey, customColor, transparency, textSize,
                    alwaysOnTop, widgetEligible, coverScreenshotBlockId, manualSortKey,
                    lifecycleState, trashedAt, conflictOriginNoteId, conflictLabel,
                    versionId, parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                note.id.uuidString,
                note.title,
                note.colorKey.rawValue,
                note.customColor,
                note.transparency,
                note.textSize,
                note.alwaysOnTop,
                note.widgetEligible,
                note.coverScreenshotBlockId?.uuidString,
                note.manualSortKey,
                note.lifecycleState.rawValue,
                note.trashedAt,
                note.conflictOriginNoteId?.uuidString,
                note.conflictLabel,
                note.versionId.uuidString,
                note.parentVersionId?.uuidString,
                note.lastModifiedDeviceId.uuidString,
                note.createdAt,
                note.modifiedAt,
            ]
        )
    }

    private func updateNoteRow(_ db: Database, note: Note) throws {
        try db.execute(
            sql: """
                UPDATE note SET
                    title = ?,
                    colorKey = ?,
                    customColor = ?,
                    transparency = ?,
                    textSize = ?,
                    alwaysOnTop = ?,
                    widgetEligible = ?,
                    coverScreenshotBlockId = ?,
                    manualSortKey = ?,
                    lifecycleState = ?,
                    trashedAt = ?,
                    conflictOriginNoteId = ?,
                    conflictLabel = ?,
                    versionId = ?,
                    parentVersionId = ?,
                    lastModifiedDeviceId = ?,
                    modifiedAt = ?
                WHERE id = ?
                """,
            arguments: [
                note.title,
                note.colorKey.rawValue,
                note.customColor,
                note.transparency,
                note.textSize,
                note.alwaysOnTop,
                note.widgetEligible,
                note.coverScreenshotBlockId?.uuidString,
                note.manualSortKey,
                note.lifecycleState.rawValue,
                note.trashedAt,
                note.conflictOriginNoteId?.uuidString,
                note.conflictLabel,
                note.versionId.uuidString,
                note.parentVersionId?.uuidString,
                note.lastModifiedDeviceId.uuidString,
                note.modifiedAt,
                note.id.uuidString,
            ]
        )
    }

    private func fetchNoteRow(_ db: Database, id: UUID) throws -> Note? {
        guard let row = try Row.fetchOne(
            db,
            sql: "SELECT * FROM note WHERE id = ?",
            arguments: [id.uuidString]
        ) else {
            return nil
        }
        return try noteFromRow(row)
    }

    private func noteFromRow(_ row: Row) throws -> Note {
        Note(
            id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
            title: row["title"],
            colorKey: NoteColorKey(rawValue: row["colorKey"] ?? "") ?? .yellow,
            customColor: row["customColor"],
            transparency: row["transparency"] ?? 0.0,
            textSize: row["textSize"] ?? 13,
            alwaysOnTop: row["alwaysOnTop"] ?? false,
            widgetEligible: row["widgetEligible"] ?? true,
            coverScreenshotBlockId: (row["coverScreenshotBlockId"] as String?).flatMap { UUID(uuidString: $0) },
            manualSortKey: row["manualSortKey"] ?? 0,
            lifecycleState: NoteLifecycleState(rawValue: row["lifecycleState"] ?? "") ?? .active,
            trashedAt: row["trashedAt"],
            conflictOriginNoteId: (row["conflictOriginNoteId"] as String?).flatMap { UUID(uuidString: $0) },
            conflictLabel: row["conflictLabel"],
            versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
            parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
            lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
            createdAt: row["createdAt"] ?? Date(),
            modifiedAt: row["modifiedAt"] ?? Date()
        )
    }

    private func insertBlockRow(_ db: Database, block: Block) throws {
        let payloadData = try canonicalEncoder.encode(block.payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        try db.execute(
            sql: """
                INSERT INTO block (
                    id, noteId, kind, sortKey, payload,
                    versionId, parentVersionId, lastModifiedDeviceId, createdAt, modifiedAt
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                block.id.uuidString,
                block.noteId.uuidString,
                block.kind.rawValue,
                block.sortKey,
                payloadString,
                block.versionId.uuidString,
                block.parentVersionId?.uuidString,
                block.lastModifiedDeviceId.uuidString,
                block.createdAt,
                block.modifiedAt,
            ]
        )
    }

    private func updateBlockRow(_ db: Database, block: Block) throws {
        let payloadData = try canonicalEncoder.encode(block.payload)
        let payloadString = String(data: payloadData, encoding: .utf8) ?? "{}"
        try db.execute(
            sql: """
                UPDATE block SET
                    kind = ?,
                    sortKey = ?,
                    payload = ?,
                    versionId = ?,
                    parentVersionId = ?,
                    lastModifiedDeviceId = ?,
                    modifiedAt = ?
                WHERE id = ?
                """,
            arguments: [
                block.kind.rawValue,
                block.sortKey,
                payloadString,
                block.versionId.uuidString,
                block.parentVersionId?.uuidString,
                block.lastModifiedDeviceId.uuidString,
                block.modifiedAt,
                block.id.uuidString,
            ]
        )
    }

    private func blockFromRow(_ row: Row) throws -> Block {
        let payloadString: String = row["payload"] ?? "{}"
        let payloadData = Data(payloadString.utf8)
        let payload = try canonicalDecoder.decode(CanonicalBlockPayload.self, from: payloadData)
        return Block(
            id: UUID(uuidString: row["id"] ?? "") ?? UUID(),
            noteId: UUID(uuidString: row["noteId"] ?? "") ?? UUID(),
            kind: BlockKind(rawValue: row["kind"] ?? "") ?? .richText,
            sortKey: row["sortKey"] ?? 0,
            payload: payload,
            versionId: UUID(uuidString: row["versionId"] ?? "") ?? UUID(),
            parentVersionId: (row["parentVersionId"] as String?).flatMap { UUID(uuidString: $0) },
            lastModifiedDeviceId: UUID(uuidString: row["lastModifiedDeviceId"] ?? "") ?? UUID(),
            createdAt: row["createdAt"] ?? Date(),
            modifiedAt: row["modifiedAt"] ?? Date()
        )
    }

    // MARK: - FTS content row maintenance

    /// Writes (or replaces) the FTS content row for a note. Called within a
    /// write transaction so the FTS5 trigger fires atomically with the note
    /// change.
    private func upsertSearchRow(
        _ db: Database,
        noteId: UUID,
        title: String,
        body: String,
        summary: String,
        todos: String,
        code: String,
        fileNames: String,
        captions: String,
        ocr: String
    ) throws {
        try db.execute(
            sql: """
                INSERT INTO note_fts_content (noteId, title, summary, body, todos, code, fileNames, captions, ocr)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(noteId) DO UPDATE SET
                    title = excluded.title,
                    summary = excluded.summary,
                    body = excluded.body,
                    todos = excluded.todos,
                    code = excluded.code,
                    fileNames = excluded.fileNames,
                    captions = excluded.captions,
                    ocr = excluded.ocr
                """,
            arguments: [
                noteId.uuidString, title, summary, body,
                todos, code, fileNames, captions, ocr,
            ]
        )
    }
}
