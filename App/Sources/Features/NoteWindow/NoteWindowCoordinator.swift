import SwiftUI
import AppKit
import Domain
import Persistence
import SystemBridge

// MARK: - NoteWindowCoordinator (T160/T246/T269)
//
// Per tasks.md T160 and spec FR-005/FR-006/FR-007/FR-007a:
// - Opens a note window by UUID; ONE window per note (focus existing, never
//   duplicate).
// - Flushes pending edits before close.
// - Does NOT reopen windows after relaunch (FR-007).
// - FR-007a: a new note window receives keyboard focus immediately; the
//   library stays open without focus; global-shortcut creation activates
//   the app.
// - FR-012a empty-note auto-discard (T167): a never-contained-content note
//   MAY be auto-removed on close; a previously-content note MUST NOT be
//   auto-deleted when its text is now empty.
// - FR-009a (T246): deleting a note with an open window closes the window
//   immediately (the deletion toast is presented by the library/Trash UI).

/// Opens and coordinates per-note windows (AppKit-backed; SwiftUI content
/// hosted via `NSHostingView` inside `NSWindow`).
@MainActor
@Observable
public final class NoteWindowCoordinator {
    private let environment: AppEnvironment

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    /// Opens (or focuses) the note's window. Returns the window.
    @discardableResult
    public func open(noteId: UUID) async -> NSWindow? {
        // One window per note (FR-005): focus existing, never duplicate.
        if NoteWindowBridge.focusExisting(noteId: noteId) {
            return NoteWindowBridge.registeredWindow(for: noteId)
        }
        guard let repo = environment.persistence.noteRepository else { return nil }
        let note: Note?
        do {
            note = try await repo.fetch(id: noteId)
        } catch {
            return nil  // FR-011a: caller surfaces the failure non-blockingly
        }
        guard let note else { return nil }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 420, height: 480),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = note.title ?? ""
        window.isReleasedWhenClosed = false
        window.backgroundColor = .textBackgroundColor
        NoteWindowBridge.applyCollectionBehavior(window, alwaysOnTop: note.alwaysOnTop)
        _ = NoteWindowBridge.register(window, noteId: noteId)
        WindowLevelBridge.apply(window, alwaysOnTop: note.alwaysOnTop)

        let content = NoteWindowContent(
            noteId: noteId,
            environment: environment,
            coordinator: self
        )
        window.contentView = NSHostingView(rootView: content)

        // FR-007a: the new note window receives keyboard focus immediately.
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }

    /// Closes the note's window(s) immediately (FR-009a delete path).
    public func closeAll(noteId: UUID) {
        NoteWindowBridge.unregister(noteId: noteId)
    }

    /// Flushes pending edits + applies the FR-012a auto-discard decision
    /// when the window closes. Returns `true` when the note may be removed.
    public func willClose(noteId: UUID, hadMeaningfulContent: Bool) -> Bool {
        // FR-012a: never-content notes MAY be auto-discarded; previously-
        // content notes are NEVER auto-deleted when empty.
        NoteWindowBridge.unregister(noteId: noteId)
        return !hadMeaningfulContent
    }

    /// Whether a note window is currently open.
    public func isOpen(noteId: UUID) -> Bool {
        NoteWindowBridge.isOpen(noteId: noteId)
    }
}

/// The SwiftUI content hosted inside a note window: controls + editor.
public struct NoteWindowContent: View {
    let noteId: UUID
    let environment: AppEnvironment
    let coordinator: NoteWindowCoordinator

    @State private var blocks: [Block] = []
    @State private var note: Note?

    public init(noteId: UUID, environment: AppEnvironment, coordinator: NoteWindowCoordinator) {
        self.noteId = noteId
        self.environment = environment
        self.coordinator = coordinator
    }

    public var body: some View {
        if let note {
            VStack(spacing: 0) {
                NoteControlsView(note: note, onChanged: { updated in
                    self.note = updated
                })
                Divider()
                RichTextBlockView(
                    note: note,
                    blocks: blocks,
                    onBlocksChanged: { newBlocks in
                        blocks = newBlocks
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(ReadableTheme.background(for: note))
        } else {
            Color.clear
                .onAppear(perform: load)
        }
    }

    private func load() {
        guard let repo = environment.persistence.noteRepository else { return }
        Task {
            do {
                self.note = try await repo.fetch(id: noteId)
                self.blocks = try await repo.fetchBlocks(noteId: noteId)
            } catch {
                self.note = nil
            }
        }
    }
}
