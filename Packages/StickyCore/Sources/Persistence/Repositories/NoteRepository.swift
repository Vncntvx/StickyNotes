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
            try db.execute(
                sql: """
                    UPDATE note
                    SET lifecycleState = 'active',
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
    }

    public func permanentlyDelete(id: UUID, deviceId: UUID) async throws {
        try await store.write { db in
            // Fetch the current versionId to record in the tombstone.
            let currentVersionId: String? = try String.fetchOne(
                db,
                sql: "SELECT versionId FROM note WHERE id = ?",
                arguments: [id.uuidString]
            )
            let priorVersionId = currentVersionId ?? UUID().uuidString

            // Insert the tombstone (sync-safety retention; data-model.md
            // §Tombstone). canPurgeRemote defaults to false — the sync
            // engine flips it once all known devices have seen the deletion.
            try db.execute(
                sql: """
                    INSERT INTO tombstone (noteId, deletedVersionId, parentVersionId, deletingDeviceId, deletedAt, canPurgeRemote)
                    VALUES (?, ?, NULL, ?, ?, 0)
                    ON CONFLICT(noteId) DO UPDATE SET
                        deletedVersionId = excluded.deletedVersionId,
                        deletingDeviceId = excluded.deletingDeviceId,
                        deletedAt = excluded.deletedAt
                    """,
                arguments: [id.uuidString, UUID().uuidString, deviceId.uuidString, Date()]
            )
            _ = priorVersionId  // lineage retained on the note row below.

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
                note.textSize.rawValue,
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
                note.textSize.rawValue,
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
            textSize: TextSize(rawValue: row["textSize"] ?? "") ?? .regular,
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
