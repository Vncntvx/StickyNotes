import Foundation

// MARK: - Canonical note document + block payload types (T015)
//
// Per contracts/note-document.schema.json and contracts/block-payloads.schema.json.
//
// These are the versioned canonical representations used for storage, export,
// and encrypted synchronization. NO Swift type names, NO platform archives,
// NO local paths, NO bookmark bytes. Schema version 1 (constitution IV).

// MARK: - Canonical block payload (oneOf per block kind)

/// Kind-specific canonical payload for a block. One of these is embedded as
/// a block's `payload`. Per contracts/block-payloads.schema.json.
public enum CanonicalBlockPayload: Sendable, Equatable, Hashable {
    case richText(RichTextDocument)
    case todo(TodoPayload)
    case code(CodePayload)
    case fileReference(FileReferencePayload)
    case image(EmbeddedImagePayload)
    case screenshot(ScreenshotPayload)
}

/// Payload for a todo block: stable todo id + nested rich text (the todo's
/// text). Identity is separate from text for stability across reorders/edits
/// (FR-071).
public struct TodoPayload: Sendable, Equatable, Hashable {
    public var todoId: UUID
    public var richText: RichTextDocument

    public init(todoId: UUID, richText: RichTextDocument) {
        self.todoId = todoId
        self.richText = richText
    }
}

/// Payload for a code block. Exact code text (whitespace/tabs/line breaks
/// preserved), optional language label. No syntax highlighting in v1.
public struct CodePayload: Sendable, Equatable, Hashable {
    public var text: String
    public var language: String?

    public init(text: String, language: String? = nil) {
        self.text = text
        self.language = language
    }
}

/// Synchronized metadata for a file-reference block. NO bookmark bytes, NO
/// absolute paths (constitution IX; contracts/block-payloads.schema.json).
public struct FileReferencePayload: Sendable, Equatable, Hashable {
    public var displayName: String
    public var contentType: String  // UTType identifier
    public var approximateSize: Int?
    public var originDeviceId: UUID
    public var addedAt: Date
    public var caption: String?

    public init(
        displayName: String,
        contentType: String,
        approximateSize: Int? = nil,
        originDeviceId: UUID,
        addedAt: Date,
        caption: String? = nil
    ) {
        self.displayName = displayName
        self.contentType = contentType
        self.approximateSize = approximateSize
        self.originDeviceId = originDeviceId
        self.addedAt = addedAt
        self.caption = caption
    }
}

/// Embedded image payload: original + thumbnail asset ids, optional caption.
public struct EmbeddedImagePayload: Sendable, Equatable, Hashable {
    public var originalAssetId: UUID
    public var thumbnailAssetId: UUID
    public var caption: String?

    public init(originalAssetId: UUID, thumbnailAssetId: UUID, caption: String? = nil) {
        self.originalAssetId = originalAssetId
        self.thumbnailAssetId = thumbnailAssetId
        self.caption = caption
    }
}

/// Screenshot association payload: original + thumbnail asset ids, optional
/// app icon, optional app name/window title/caption, capture time, cover
/// flag. At most one `isCover = true` per note (transactional).
public struct ScreenshotPayload: Sendable, Equatable, Hashable {
    public var originalAssetId: UUID
    public var thumbnailAssetId: UUID
    public var appIconAssetId: UUID?
    public var applicationName: String?
    public var windowTitle: String?
    public var caption: String?
    public var capturedAt: Date
    public var isCover: Bool

    public init(
        originalAssetId: UUID,
        thumbnailAssetId: UUID,
        appIconAssetId: UUID? = nil,
        applicationName: String? = nil,
        windowTitle: String? = nil,
        caption: String? = nil,
        capturedAt: Date,
        isCover: Bool = false
    ) {
        self.originalAssetId = originalAssetId
        self.thumbnailAssetId = thumbnailAssetId
        self.appIconAssetId = appIconAssetId
        self.applicationName = applicationName
        self.windowTitle = windowTitle
        self.caption = caption
        self.capturedAt = capturedAt
        self.isCover = isCover
    }
}

// MARK: - Canonical block (envelope around payload)

/// The canonical block envelope: identity + kind + sort + version lineage
/// + payload. Per contracts/block-payloads.schema.json. Schema version 1.
public struct CanonicalBlock: Sendable, Codable, Equatable, Hashable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var noteId: UUID
    public var kind: BlockKind
    public var sortKey: Int
    public var versionId: UUID
    public var parentVersionId: UUID?
    public var lastModifiedDeviceId: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var payload: CanonicalBlockPayload

    public init(
        id: UUID = UUID(),
        noteId: UUID,
        kind: BlockKind,
        sortKey: Int,
        versionId: UUID = UUID(),
        parentVersionId: UUID? = nil,
        lastModifiedDeviceId: UUID,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        payload: CanonicalBlockPayload,
        schemaVersion: Int = CanonicalBlock.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.noteId = noteId
        self.kind = kind
        self.sortKey = sortKey
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.payload = payload
    }

    /// Convenience conversion from the runtime `Block`.
    public init(block: Block) {
        self.init(
            id: block.id,
            noteId: block.noteId,
            kind: block.kind,
            sortKey: block.sortKey,
            versionId: block.versionId,
            parentVersionId: block.parentVersionId,
            lastModifiedDeviceId: block.lastModifiedDeviceId,
            createdAt: block.createdAt,
            modifiedAt: block.modifiedAt,
            payload: block.payload
        )
    }
}

// MARK: - Canonical note document

/// The versioned canonical representation of a note for storage, export, and
/// encrypted synchronization. NO Swift type names, NO platform archives, NO
/// local paths, NO bookmark bytes. Schema version 1.
///
/// Per contracts/note-document.schema.json.
public struct CanonicalNote: Sendable, Codable, Equatable, Hashable {
    public static let schemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var title: String?
    public var colorKey: NoteColorKey
    public var customColor: String?
    public var transparency: Double
    public var textSize: TextSize
    public var alwaysOnTop: Bool
    public var widgetEligible: Bool
    public var coverScreenshotBlockId: UUID?
    public var manualSortKey: Int
    public var lifecycleState: NoteLifecycleState
    public var trashedAt: Date?
    public var conflictOriginNoteId: UUID?
    public var conflictLabel: String?
    public var versionId: UUID
    public var parentVersionId: UUID?
    public var lastModifiedDeviceId: UUID
    public var createdAt: Date
    public var modifiedAt: Date
    public var blocks: [CanonicalBlock]

    public init(
        schemaVersion: Int = CanonicalNote.schemaVersion,
        id: UUID,
        title: String? = nil,
        colorKey: NoteColorKey,
        customColor: String? = nil,
        transparency: Double,
        textSize: TextSize,
        alwaysOnTop: Bool,
        widgetEligible: Bool,
        coverScreenshotBlockId: UUID? = nil,
        manualSortKey: Int,
        lifecycleState: NoteLifecycleState,
        trashedAt: Date? = nil,
        conflictOriginNoteId: UUID? = nil,
        conflictLabel: String? = nil,
        versionId: UUID,
        parentVersionId: UUID? = nil,
        lastModifiedDeviceId: UUID,
        createdAt: Date,
        modifiedAt: Date,
        blocks: [CanonicalBlock]
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.title = title
        self.colorKey = colorKey
        self.customColor = customColor
        self.transparency = transparency
        self.textSize = textSize
        self.alwaysOnTop = alwaysOnTop
        self.widgetEligible = widgetEligible
        self.coverScreenshotBlockId = coverScreenshotBlockId
        self.manualSortKey = manualSortKey
        self.lifecycleState = lifecycleState
        self.trashedAt = trashedAt
        self.conflictOriginNoteId = conflictOriginNoteId
        self.conflictLabel = conflictLabel
        self.versionId = versionId
        self.parentVersionId = parentVersionId
        self.lastModifiedDeviceId = lastModifiedDeviceId
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.blocks = blocks
    }

    /// Convenience conversion from the runtime `Note` + `[Block]` pair
    /// (T015: canonical note document conforms to note-document.schema.json).
    public init(note: Note, blocks: [Block]) {
        self.init(
            id: note.id,
            title: note.title,
            colorKey: note.colorKey,
            customColor: note.customColor,
            transparency: note.transparency,
            textSize: note.textSize,
            alwaysOnTop: note.alwaysOnTop,
            widgetEligible: note.widgetEligible,
            coverScreenshotBlockId: note.coverScreenshotBlockId,
            manualSortKey: note.manualSortKey,
            lifecycleState: note.lifecycleState,
            trashedAt: note.trashedAt,
            conflictOriginNoteId: note.conflictOriginNoteId,
            conflictLabel: note.conflictLabel,
            versionId: note.versionId,
            parentVersionId: note.parentVersionId,
            lastModifiedDeviceId: note.lastModifiedDeviceId,
            createdAt: note.createdAt,
            modifiedAt: note.modifiedAt,
            blocks: blocks.map { CanonicalBlock(block: $0) }
        )
    }

    /// Convenience conversion back to the runtime `Note`.
    public var runtimeNote: Note {
        Note(
            id: id,
            title: title,
            colorKey: colorKey,
            customColor: customColor,
            transparency: transparency,
            textSize: textSize,
            alwaysOnTop: alwaysOnTop,
            widgetEligible: widgetEligible,
            coverScreenshotBlockId: coverScreenshotBlockId,
            manualSortKey: manualSortKey,
            lifecycleState: lifecycleState,
            trashedAt: trashedAt,
            conflictOriginNoteId: conflictOriginNoteId,
            conflictLabel: conflictLabel,
            versionId: versionId,
            parentVersionId: parentVersionId,
            lastModifiedDeviceId: lastModifiedDeviceId,
            createdAt: createdAt,
            modifiedAt: modifiedAt
        )
    }
}
