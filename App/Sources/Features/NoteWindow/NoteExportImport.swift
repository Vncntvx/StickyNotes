import SwiftUI
import AppKit
import Domain
import EditorCore

// MARK: - NoteExportImport (T233/T248, FR-031a/FR-031)
//
// Per tasks.md T233/T248 and spec FR-031a/FR-031: single-note JSON
// export/import reusing the canonical note-envelope schema; duplicate note;
// copy note as Markdown. File-reference blocks export generic metadata only
// — never bookmark bytes or absolute paths (FR-105). Import fails closed
// with NO partial note (NoteDocumentSerializer). Save/Open panels go through
// NSSavePanel/NSOpenPanel (sandbox user-selected locations).

/// Export/import + duplicate + Markdown-copy actions for a note.
public enum NoteExportImport {

    /// Exports a note as JSON via NSSavePanel. Returns whether the user
    /// completed the save.
    @MainActor
    public static func exportNoteAsJSON(note: Note, blocks: [Block], assetBytes: [UUID: Data] = [:]) -> Bool {
        do {
            let document = try NoteDocumentSerializer.exportDocument(note: note, blocks: blocks, assetBytes: assetBytes)
            let data = try NoteDocumentSerializer.encodeDocument(document)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "\(note.title ?? "note").json"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Imports a note JSON via NSOpenPanel. Fails closed on unsupported/
    /// corrupted documents (no partial note); the caller inserts the parsed
    /// note through the repository path (T030). Returns the parsed note.
    @MainActor
    public static func importNoteJSON() throws -> CanonicalNote? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try Data(contentsOf: url)
        let document = try NoteDocumentSerializer.decodeDocument(from: data)
        // Fail closed: reject documents that fail structural validation.
        if let reason = NoteDocumentSerializer.validateForImport(document) {
            throw NoteDocumentError.corruptedEnvelope(reason)
        }
        return document
    }

    /// Copies the note as Markdown to the clipboard (FR-031).
    public static func copyNoteAsMarkdown(note: Note, blocks: [Block]) {
        let markdown = NoteMarkdownSerializer.markdown(note: note, blocks: blocks)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
