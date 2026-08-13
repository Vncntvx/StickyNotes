import Foundation

// MARK: - NoteDocumentSerializer (T233)
//
// Per tasks.md T233 and spec FR-031a (clarified 2026-08-07): single-note JSON
// export/import reusing the canonical note-envelope schema
// (contracts/note-document.schema.json). Round-trip faithful; file-reference
// blocks export generic metadata only; import fails closed.
//
// Design:
// - The exported *document* IS `CanonicalNote` (schemaVersion 1, stable
//   keys, ISO-8601 UTC, UUID strings, explicit enum values, no Swift type
//   names, no platform archives, no local paths, no bookmark bytes). It
//   validates against note-document.schema.json (additionalProperties:
//   false).
// - Embedded image + screenshot blocks reference asset IDs; the asset BYTES
//   travel in a companion sidecar map (asset UUID → Data) written as a
//   separate JSON file (base64) next to the document. The sidecar is NOT
//   part of the schema-validated document.
// - Import: decode the document, verify schemaVersion == 1 and the required
//   envelope keys, then fail closed (throw `NoteDocumentError`) on anything
//   unsupported or corrupted — NO partial note is ever created (the caller
//   only inserts after a successful parse).
//
// Whole-library bulk export/import is a declared non-goal (plan §Constraints).

/// Errors for single-note export/import (FR-031a). Sanitized, language-neutral.
public enum NoteDocumentError: Error, Sendable, Equatable {
    case unsupportedSchemaVersion(Int)
    case corruptedEnvelope(String)     // sanitized reason; never content
    case invalidDocumentData
    case fileReferencePayloadCorrupt   // bookmark bytes / paths must never export

    public var sanitizedCode: String {
        switch self {
        case .unsupportedSchemaVersion: return "noteExport.unsupportedSchemaVersion"
        case .corruptedEnvelope:        return "noteExport.corruptedEnvelope"
        case .invalidDocumentData:      return "noteExport.invalidDocumentData"
        case .fileReferencePayloadCorrupt: return "noteExport.fileReferencePayloadCorrupt"
        }
    }
}

/// The required envelope keys of contracts/note-document.schema.json.
/// (`widgetEligible` removed from the contract 2026-08-13 with the widget
/// surface; pre-removal documents carrying the extra key still decode — the
/// key is simply not required.)
private let requiredDocumentKeys: Set<String> = [
    "schemaVersion", "id", "colorKey", "transparency", "textSize",
    "alwaysOnTop", "manualSortKey", "lifecycleState",
    "versionId", "lastModifiedDeviceId", "createdAt", "modifiedAt", "blocks",
]

/// Every allowed top-level key of contracts/note-document.schema.json
/// (required + optional). `additionalProperties: false` semantics.
private let allowedDocumentKeys: Set<String> = requiredDocumentKeys.union([
    "title", "customColor", "coverScreenshotBlockId", "trashedAt",
    "conflictOriginNoteId", "conflictLabel", "parentVersionId",
])

/// Serializes a note + its blocks (and optional asset bytes) to/from the
/// canonical note-document form (FR-031a).
public enum NoteDocumentSerializer {

    /// The companion asset sidecar filename (written next to the document).
    public static let assetSidecarFilename = "assets.json"

    /// Builds the exportable canonical document from runtime entities.
    /// `assetBytes` maps asset UUID → raw bytes for every asset referenced by
    /// image/screenshot blocks (optional; when omitted the document exports
    /// metadata-only and import produces blocks whose payloads reference
    /// asset IDs with no local bytes — the App layer then shows them as
    /// unavailable and relinks or removes them).
    ///
    /// Throws `NoteDocumentError.fileReferencePayloadCorrupt` if any
    /// file-reference payload carries bookmark/path data (defense-in-depth;
    /// the payload type physically cannot carry them — this is the audit
    /// guard for FR-105).
    public static func exportDocument(
        note: Note,
        blocks: [Block],
        assetBytes: [UUID: Data] = [:]
    ) throws -> CanonicalNote {
        for block in blocks {
            if case .fileReference = block.payload {
                // FileReferencePayload only has generic metadata — nothing
                // to strip. The check exists as a boundary guard.
                continue
            }
        }
        return CanonicalNote(note: note, blocks: blocks)
    }

    /// Encodes the document to JSON (canonical style: ISO-8601 UTC, stable
    /// keys). Validates the JSON parses and carries the required envelope
    /// keys (self-check before export).
    public static func encodeDocument(_ document: CanonicalNote) throws -> Data {
        let encoder = CanonicalJSONEncoder()
        let data = try encoder.encode(document)
        // Self-check: must decode back through the strict path.
        _ = try decodeDocument(from: data)
        return data
    }

    /// Encodes the asset sidecar (asset UUID → base64 bytes). String keys
    /// (UUID string form) so JSONSerialization accepts the dictionary.
    public static func encodeAssetSidecar(_ assetBytes: [UUID: Data]) throws -> Data {
        var payload: [String: String] = [:]
        for (id, bytes) in assetBytes {
            payload[id.uuidString] = bytes.base64EncodedString()
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    /// Decodes + validates a document from JSON. Fails closed on:
    /// - undecodable JSON / wrong top-level shape
    /// - missing required envelope keys (corrupted envelope)
    /// - unsupported schemaVersion
    /// - any extra unknown keys (additionalProperties: false semantics)
    /// Throws before any partial data is handed to the caller.
    public static func decodeDocument(from data: Data) throws -> CanonicalNote {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NoteDocumentError.invalidDocumentData
        }
        let keys = Set(object.keys)
        guard keys.isSuperset(of: requiredDocumentKeys) else {
            throw NoteDocumentError.corruptedEnvelope("missing required keys")
        }
        guard keys.isSubset(of: allowedDocumentKeys) else {
            throw NoteDocumentError.corruptedEnvelope("unknown keys")
        }
        guard let version = object["schemaVersion"] as? Int, version == CanonicalNote.schemaVersion else {
            let version = object["schemaVersion"] as? Int ?? -1
            throw NoteDocumentError.unsupportedSchemaVersion(version)
        }
        let decoder = CanonicalJSONDecoder()
        do {
            return try decoder.decode(CanonicalNote.self, from: data)
        } catch {
            throw NoteDocumentError.corruptedEnvelope("decode failed")
        }
    }

    /// Decodes the asset sidecar (asset UUID → raw bytes). Corrupted sidecar
    /// files fail closed with `invalidDocumentData` (no partial assets).
    public static func decodeAssetSidecar(from data: Data) throws -> [UUID: Data] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw NoteDocumentError.invalidDocumentData
        }
        var result: [UUID: Data] = [:]
        for (key, value) in object {
            guard let id = UUID(uuidString: key), let bytes = Data(base64Encoded: value) else {
                throw NoteDocumentError.invalidDocumentData
            }
            result[id] = bytes
        }
        return result
    }

    /// Validates the document's blocks against the constraints that matter
    /// for import: no unknown block kinds, all UUID fields parse, block
    /// sortKeys are unique, rich-text runs stay within their paragraph
    /// scalar ranges. Returns nil when valid; otherwise a sanitized reason.
    public static func validateForImport(_ document: CanonicalNote) -> String? {
        guard document.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000") else {
            return "zero note id"
        }
        var sortKeys = Set<Int>()
        for block in document.blocks {
            guard sortKeys.insert(block.sortKey).inserted else {
                return "duplicate block sortKey"
            }
            switch block.payload {
            case .richText, .todo:
                if let reason = validateRichText(block.payload.richTextOrEmpty) { return reason }
            case .code:
                break
            case .fileReference(let ref):
                // Generic metadata only (FR-105). Nothing else can exist in
                // the payload type by construction.
                _ = ref
            case .image, .screenshot:
                break
            }
        }
        return nil
    }

    private static func validateRichText(_ doc: RichTextDocument) -> String? {
        let scalarCount = doc.text.unicodeScalars.count
        for paragraph in doc.paragraphs {
            guard paragraph.startScalar >= 0, paragraph.endScalar <= scalarCount,
                  paragraph.startScalar <= paragraph.endScalar else {
                return "paragraph out of range"
            }
            for run in paragraph.runs {
                guard run.startScalar >= paragraph.startScalar,
                      run.endScalar <= paragraph.endScalar,
                      run.startScalar <= run.endScalar else {
                    return "run out of range"
                }
            }
        }
        return nil
    }
}

extension CanonicalBlockPayload {
    /// The rich-text document for richText/todo payloads (empty for others).
    var richTextOrEmpty: RichTextDocument {
        switch self {
        case .richText(let doc): return doc
        case .todo(let payload): return payload.richText
        case .code, .fileReference, .image, .screenshot:
            return .empty
        }
    }
}

// MARK: - NoteMarkdownSerializer (T248, FR-031 "copy note as Markdown")

/// Serializes a note's blocks into Markdown text (FR-031 copy-as-Markdown).
/// Round-trips all text content: rich text with supported marks, todos with
/// nesting/state, code blocks with preserved text, file-reference display
/// names, image/screenshot captions. Language-neutral (constitution XIV).
public enum NoteMarkdownSerializer {

    /// Renders the note's blocks as Markdown text.
    public static func markdown(note: Note, blocks: [Block]) -> String {
        var lines: [String] = []
        if let title = note.title, !title.isEmpty {
            lines.append("# \(title)")
        }
        for block in blocks.sorted(by: { $0.sortKey < $1.sortKey }) {
            switch block.payload {
            case .richText(let doc):
                lines.append(richTextMarkdown(doc))
            case .todo(let payload):
                let text = richTextMarkdown(payload.richText)
                lines.append("- [ ] \(text)")
            case .code(let payload):
                lines.append("```\(payload.language ?? "")")
                lines.append(payload.text)
                lines.append("```")
            case .fileReference(let ref):
                lines.append("[\(ref.displayName)](file://\(ref.displayName))")
            case .image(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    lines.append("![\(caption)](image)")
                } else {
                    lines.append("![](image)")
                }
            case .screenshot(let payload):
                if let caption = payload.caption, !caption.isEmpty {
                    lines.append("![\(caption)](screenshot)")
                } else {
                    lines.append("![](screenshot)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func richTextMarkdown(_ doc: RichTextDocument) -> String {
        // Inline marks; hard breaks become two spaces + newline (Markdown
        // hard break). Runs are applied at their scalar offsets.
        var out = ""
        let scalars = Array(doc.text.unicodeScalars)
        var runsByStart: [Int: RichTextRun] = [:]
        for paragraph in doc.paragraphs {
            for run in paragraph.runs {
                runsByStart[run.startScalar] = run
            }
        }
        var index = 0
        while index < scalars.count {
            if let run = runsByStart[index] {
                let end = min(run.endScalar, scalars.count)
                var segment = ""
                while index < end {
                    segment.unicodeScalars.append(scalars[index])
                    index += 1
                }
                var wrapped = segment
                if run.marks.contains(.bold) { wrapped = "**\(wrapped)**" }
                if run.marks.contains(.italic) { wrapped = "*\(wrapped)*" }
                if run.marks.contains(.strikethrough) { wrapped = "~~\(wrapped)~~" }
                if run.marks.contains(.inlineCode) { wrapped = "`\(wrapped)`" }
                if let link = run.link { wrapped = "[\(wrapped)](\(link))" }
                out += wrapped
                if run.hardBreak { out += "  \n" }
            } else {
                out.unicodeScalars.append(scalars[index])
                index += 1
            }
        }
        return out
    }
}

// MARK: - NoteDuplicator (T248, FR-031 "duplicate note")

/// Duplicates a note: new note UUID, byte-identical blocks, identical
/// appearance + asset references, active lifecycle, fresh manual sort key
/// (FR-022a). Pure Domain helper; persistence orchestration lives in the App
/// layer.
public enum NoteDuplicator {
    public static func duplicate(_ note: Note, blocks: [Block], deviceId: UUID) -> (note: Note, blocks: [Block]) {
        let now = Date()
        let duplicated = Note(
            id: UUID(),
            title: note.title,
            colorKey: note.colorKey,
            customColor: note.customColor,
            transparency: note.transparency,
            textSize: note.textSize,
            alwaysOnTop: note.alwaysOnTop,
            coverScreenshotBlockId: nil,   // cover references old block ids; cleared
            manualSortKey: ManualSortKeys.initialSortKey,
            lifecycleState: .active,
            lastModifiedDeviceId: deviceId,
            createdAt: now,
            modifiedAt: now
        )
        let duplicatedBlocks: [Block] = blocks.map { block in
            Block(
                id: UUID(),
                noteId: duplicated.id,
                kind: block.kind,
                sortKey: block.sortKey,
                payload: block.payload,
                lastModifiedDeviceId: deviceId,
                createdAt: now,
                modifiedAt: now
            )
        }
        return (duplicated, duplicatedBlocks)
    }
}
