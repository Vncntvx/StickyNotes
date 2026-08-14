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
//
// R1.7 (remediation-phase1 T028-T031): the import path and the asset
// sidecar are now REAL — previously the import did not exist (a dangling
// doc comment claimed one, audit S-8) and export silently dropped the
// asset bytes (the sidecar was never written — export lost every image).
// The panel-free core (`importNoteDocument` / `writeExport`) is testable
// without UI; the panel wrappers below are thin.

/// Export/import + duplicate + Markdown-copy actions for a note.
public enum NoteExportImport {

    /// Core export (no UI): writes the canonical document JSON and, when
    /// asset bytes are present, the companion sidecar
    /// (`NoteDocumentSerializer.assetSidecarFilename`) next to it.
    /// - Returns: the written document URL + the sidecar URL (nil when
    ///   there are no asset bytes).
    public static func writeExport(
        note: Note,
        blocks: [Block],
        assetBytes: [UUID: Data],
        to directory: URL
    ) throws -> (document: URL, sidecar: URL?) {
        let document = NoteDocumentSerializer.exportDocument(note: note, blocks: blocks, assetBytes: assetBytes)
        let data = try NoteDocumentSerializer.encodeDocument(document)
        let safeName = (note.title ?? "note")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let documentURL = directory.appendingPathComponent("\(safeName).json")
        try data.write(to: documentURL, options: .atomic)

        var sidecarURL: URL?
        if !assetBytes.isEmpty {
            let sidecar = try NoteDocumentSerializer.encodeAssetSidecar(assetBytes)
            let url = directory.appendingPathComponent(NoteDocumentSerializer.assetSidecarFilename)
            try sidecar.write(to: url, options: .atomic)
            sidecarURL = url
        }
        return (documentURL, sidecarURL)
    }

    /// Core import (no UI): parses + validates the canonical document,
    /// imports the sidecar asset bytes into the AssetStore under the
    /// referenced ids, and writes the note + blocks through the repository.
    /// FAILS CLOSED: any parse/validation error throws BEFORE any write —
    /// no partial note is ever created (FR-031a); an existing note id is
    /// refused (no silent overwrite).
    public static func importNoteDocument(
        data: Data,
        sidecarData: Data?,
        environment: AppEnvironment
    ) async throws -> CanonicalNote {
        // 1. Parse + validate everything BEFORE any write (fail closed).
        let document = try NoteDocumentSerializer.decodeDocument(from: data)
        if let reason = NoteDocumentSerializer.validateForImport(document) {
            throw NoteDocumentError.corruptedEnvelope(reason)
        }
        guard let repo = environment.persistence.noteRepository else {
            throw StickyError.persistence(.databaseOpenFailed)
        }
        if try await repo.fetch(id: document.id) != nil {
            throw NoteDocumentError.corruptedEnvelope("note id already exists")
        }

        // 2. Import asset bytes (optional sidecar — metadata-only import is
        //    valid; referenced assets without bytes stay unavailable).
        var assetBytes: [UUID: Data] = [:]
        if let sidecarData {
            assetBytes = try NoteDocumentSerializer.decodeAssetSidecar(from: sidecarData)
        }
        if let assetStore = environment.assets.store {
            var assetKinds: [UUID: AssetKind] = [:]
            for block in document.blocks {
                switch block.payload {
                case .image(let p):
                    assetKinds[p.originalAssetId] = .original
                    if let t = p.thumbnailAssetId { assetKinds[t] = .thumbnail }
                case .screenshot(let p):
                    assetKinds[p.originalAssetId] = .original
                    if let t = p.thumbnailAssetId { assetKinds[t] = .thumbnail }
                default:
                    break
                }
            }
            for (id, kind) in assetKinds {
                guard let bytes = assetBytes[id] else { continue }
                _ = try await assetStore.importData(bytes, id: id, kind: kind, contentType: "public.png")
            }
        }

        // 3. Write the note + blocks.
        let note = document.runtimeNote
        try await repo.create(note)
        for block in document.blocks {
            try await repo.insert(Block(
                id: block.id,
                noteId: note.id,
                kind: block.kind,
                sortKey: block.sortKey,
                payload: block.payload,
                versionId: block.versionId,
                parentVersionId: block.parentVersionId,
                lastModifiedDeviceId: block.lastModifiedDeviceId,
                createdAt: block.createdAt,
                modifiedAt: block.modifiedAt
            ))
        }
        return document
    }

    /// Exports a note as JSON via NSSavePanel (document + asset sidecar).
    /// Returns whether the user completed the save.
    @MainActor
    public static func exportNoteAsJSON(note: Note, blocks: [Block], assetBytes: [UUID: Data] = [:]) -> Bool {
        do {
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            let safeName = (note.title ?? "note")
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            panel.nameFieldStringValue = "\(safeName).json"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            let directory = url.deletingLastPathComponent()
            _ = try writeExport(note: note, blocks: blocks, assetBytes: assetBytes, to: directory)
            // The panel picked a specific filename; ensure the document
            // lands exactly there (writeExport may have sanitized the name).
            let document = NoteDocumentSerializer.exportDocument(note: note, blocks: blocks, assetBytes: assetBytes)
            let data = try NoteDocumentSerializer.encodeDocument(document)
            try data.write(to: url, options: .atomic)
            if !assetBytes.isEmpty {
                let sidecar = try NoteDocumentSerializer.encodeAssetSidecar(assetBytes)
                let sidecarURL = directory.appendingPathComponent(NoteDocumentSerializer.assetSidecarFilename)
                try sidecar.write(to: sidecarURL, options: .atomic)
            }
            return true
        } catch {
            return false
        }
    }

    /// Imports a note JSON via NSOpenPanel (R1.7 — FR-031a import path).
    /// Reads the document + the sibling asset sidecar (when present) and
    /// delegates to the fail-closed core. Returns the imported document,
    /// or nil when the user cancelled the panel.
    @MainActor
    public static func importNoteAsJSON(environment: AppEnvironment) async throws -> CanonicalNote? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let data = try Data(contentsOf: url)
        let sidecarURL = url.deletingLastPathComponent()
            .appendingPathComponent(NoteDocumentSerializer.assetSidecarFilename)
        let sidecarData = try? Data(contentsOf: sidecarURL)
        return try await importNoteDocument(data: data, sidecarData: sidecarData, environment: environment)
    }

    /// Copies the note as Markdown to the clipboard (FR-031).
    public static func copyNoteAsMarkdown(note: Note, blocks: [Block]) {
        let markdown = NoteMarkdownSerializer.markdown(note: note, blocks: blocks)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }
}
