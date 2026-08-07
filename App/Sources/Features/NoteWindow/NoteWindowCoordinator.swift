import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Domain
import Persistence
import SystemBridge

// MARK: - NoteWindowCoordinator (T160/T246/T269/T281/T289)
//
// Per tasks.md T160/T246/T269 and spec FR-005/FR-006/FR-007/FR-007a:
// - Opens a note window by UUID; ONE window per note (focus existing, never
//   duplicate).
// - Flushes pending edits before close (T281 host).
// - Does NOT reopen windows after relaunch (FR-007).
// - FR-007a: a new note window receives keyboard focus immediately; the
//   library stays open without focus; global-shortcut creation activates
//   the app.
// - FR-012a empty-note auto-discard (T167/T281): a never-contained-content
//   note MAY be auto-removed on close; a previously-content note MUST NOT be
//   auto-deleted when its text is now empty.
// - FR-009a (T246): deleting a note with an open window closes the window
//   immediately (the deletion toast is presented by the library/Trash UI).
// - FR-032/FR-033 (T289): window frame persistence via WindowStateRepository
//   (device-local) + display-change correction via DisplayChangeBridge.

/// Opens and coordinates per-note windows (AppKit-backed; SwiftUI content
/// hosted via `NSHostingView` inside `NSWindow`).
@MainActor
@Observable
public final class NoteWindowCoordinator {
    private let environment: AppEnvironment
    /// FR-009a deletion-toast hook (set by the App layer; presents the
    /// localized deletion outcome non-blockingly).
    public var deletionToast: (String) -> Void = { _ in }

    /// Main-actor-only access pattern (like NoteWindowBridge's registry
    /// lock); removed in deinit. `@ObservationIgnored`: not part of the
    /// observable state.
    @ObservationIgnored private nonisolated(unsafe) var displayObserver: NSObjectProtocol?

    public init(environment: AppEnvironment) {
        self.environment = environment
        // FR-033: display connect/disconnect → re-apply corrected frames for
        // all open note windows (preferred frames preserved per display).
        displayObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reapplyFrames()
            }
        }
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
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

        let host = NoteWindowHostModel(noteId: noteId, environment: environment)
        let content = NoteWindowContent(noteId: noteId, host: host, environment: environment, coordinator: self)
        window.contentView = NSHostingView(rootView: content)

        // FR-032/FR-033 (T289): restore the remembered frame (corrected for
        // the current display arrangement; the disconnected-display preferred
        // frame is preserved untouched).
        restoreFrame(for: window, noteId: noteId)

        let delegate = NoteWindowDelegate(
            noteId: noteId,
            coordinator: self,
            host: host,
            windowStateRepository: environment.persistence.windowStateRepository
        )
        window.delegate = delegate

        // FR-007a: the new note window receives keyboard focus immediately.
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }

    /// Closes the note's window(s) immediately (FR-009a delete path).
    public func closeAll(noteId: UUID) {
        NoteWindowBridge.registeredWindow(for: noteId)?.close()
        NoteWindowBridge.unregister(noteId: noteId)
    }

    /// Whether a note window is currently open.
    public func isOpen(noteId: UUID) -> Bool {
        NoteWindowBridge.isOpen(noteId: noteId)
    }

    // MARK: - FR-032/FR-033 window frames (T289)

    /// Restores the note's remembered frame, corrected for the current
    /// display arrangement (FR-032/FR-033).
    private func restoreFrame(for window: NSWindow, noteId: UUID) {
        guard let repo = environment.persistence.windowStateRepository else { return }
        Task {
            guard let state = try? await repo.fetch(noteId: noteId),
                  state.frame.width > 0, state.frame.height > 0 else { return }
            let displays = DisplayObservation.currentDisplayFrames()
            let preferred = NSRect(x: state.frame.x, y: state.frame.y, width: state.frame.width, height: state.frame.height)
            let fallback = state.fallbackFrame.map { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            let corrected = DisplayChangeBridge.correctedFrame(
                frame: preferred,
                preferredDisplayUUID: state.preferredDisplayUUID,
                fallbackFrame: fallback,
                displays: displays
            )
            window.setFrame(corrected, display: false)
        }
    }

    /// Re-applies corrected frames for every open note window after a display
    /// change (FR-033).
    private func reapplyFrames() {
        let displays = DisplayObservation.currentDisplayFrames()
        guard let repo = environment.persistence.windowStateRepository else { return }
        for (noteId, registration) in NoteWindowBridge.allRegistrations() {
            guard let window = registration.windowRef.window() else { continue }
            Task {
                guard let state = try? await repo.fetch(noteId: noteId),
                      state.frame.width > 0 else { return }
                let preferred = NSRect(x: state.frame.x, y: state.frame.y, width: state.frame.width, height: state.frame.height)
                let fallback = state.fallbackFrame.map { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
                let corrected = DisplayChangeBridge.correctedFrame(
                    frame: preferred,
                    preferredDisplayUUID: state.preferredDisplayUUID,
                    fallbackFrame: fallback,
                    displays: displays
                )
                window.setFrame(corrected, display: false)
            }
        }
    }
}

// MARK: - NoteWindowDelegate (T281/T289)

/// Per-window delegate: saves the frame on move/resize, flushes pending
/// edits + applies the FR-012a auto-discard decision on close.
@MainActor
private final class NoteWindowDelegate: NSObject, NSWindowDelegate {
    private let noteId: UUID
    private weak var coordinator: NoteWindowCoordinator?
    private weak var host: NoteWindowHostModel?
    private let windowStateRepository: SQLiteWindowStateRepository?

    init(
        noteId: UUID,
        coordinator: NoteWindowCoordinator,
        host: NoteWindowHostModel,
        windowStateRepository: SQLiteWindowStateRepository?
    ) {
        self.noteId = noteId
        self.coordinator = coordinator
        self.host = host
        self.windowStateRepository = windowStateRepository
    }

    func windowDidMove(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowDidResize(_ notification: Notification) {
        saveFrame(from: notification)
    }

    func windowWillClose(_ notification: Notification) {
        saveFrame(from: notification)
        // FR-141a flush + FR-012a auto-discard decision.
        guard let host else { return }
        Task {
            let mayRemove = await host.close()
            guard mayRemove, let repo = host.environment.persistence.noteRepository else { return }
            try? await repo.permanentlyDelete(id: noteId, deviceId: DeviceIdentity.current.id)
        }
    }

    private func saveFrame(from notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let displays = DisplayObservation.currentDisplayFrames()
        let best = DisplayChangeBridge.bestDisplay(for: window.frame, among: displays)
        let frame = WindowFrame(
            x: Double(window.frame.origin.x),
            y: Double(window.frame.origin.y),
            width: Double(window.frame.width),
            height: Double(window.frame.height)
        )
        Task {
            try? await windowStateRepository?.updateFrame(
                noteId: noteId,
                frame: frame,
                preferredDisplayUUID: best?.displayUUID
            )
        }
    }
}

// MARK: - NoteWindowContent (T160/T281/T282)

/// The SwiftUI content hosted inside a note window: controls + editor.
public struct NoteWindowContent: View {
    let noteId: UUID
    let environment: AppEnvironment
    let coordinator: NoteWindowCoordinator

    @State private var host: NoteWindowHostModel?

    public init(noteId: UUID, environment: AppEnvironment, coordinator: NoteWindowCoordinator) {
        self.noteId = noteId
        self.environment = environment
        self.coordinator = coordinator
    }

    public init(noteId: UUID, host: NoteWindowHostModel, environment: AppEnvironment, coordinator: NoteWindowCoordinator) {
        self.noteId = noteId
        self.environment = environment
        self.coordinator = coordinator
        _host = State(initialValue: host)
    }

    public var body: some View {
        Group {
            if let host, let note = host.note {
                VStack(spacing: 0) {
                    NoteControlsView(
                        note: note,
                        onChanged: { updated in
                            host.updateAppearance(updated)
                        },
                        onAddScreenshot: {
                            captureScreenshot()
                        },
                        onAddFileReference: {
                            pickAndInsertFileReference()
                        },
                        onDuplicate: {
                            duplicateNote(host: host)
                        },
                        onCopyAsMarkdown: {
                            NoteExportImport.copyNoteAsMarkdown(note: host.note ?? note, blocks: host.blocks)
                        },
                        onExport: {
                            _ = NoteExportImport.exportNoteAsJSON(note: host.note ?? note, blocks: host.blocks)
                        },
                        onMoveToTrash: {
                            moveToTrash(host: host)
                        }
                    )
                    Divider()
                    RichTextBlockView(
                        note: note,
                        blocks: host.blocks,
                        onBlocksChanged: { newBlocks in
                            host.updateBlocks(newBlocks)
                        },
                        onStructuralBlocksChanged: { newBlocks in
                            host.updateBlocks(newBlocks, isStructural: true)
                        },
                        onInsertTodo: {
                            Task { await host.insertTodoBlock() }
                        },
                        onInsertCode: {
                            Task { await host.insertCodeBlock() }
                        },
                        onInsertFileReference: {
                            pickAndInsertFileReference()
                        },
                        onCaptureScreenshot: {
                            captureScreenshot()
                        },
                        todoProvider: { blockId in
                            await host.todoItem(forBlock: blockId)
                        },
                        onToggleTodo: { blockId in
                            // Completion flips from the CURRENT state.
                            if let item = await host.todoItem(forBlock: blockId) {
                                await host.setTodoComplete(blockId: blockId, isComplete: !item.isComplete)
                            }
                        },
                        onDeleteTodo: { blockId in
                            await host.deleteTodo(blockId: blockId)
                        },
                        onIndentTodo: { blockId in
                            await host.indentTodo(blockId: blockId)
                        },
                        onOutdentTodo: { blockId in
                            await host.outdentTodo(blockId: blockId)
                        },
                        onMoveTodo: { blockId, direction in
                            await host.reorderTodo(blockId: blockId, direction: direction)
                        },
                        onFileAction: { blockId, action in
                            await host.performFileAction(blockId: blockId, action: action)
                        },
                        onSetCover: { blockId, isCover in
                            await host.setCover(blockId: blockId, isCover: isCover)
                        },
                        onUpdateCaption: { blockId, caption in
                            await host.updateCaption(blockId: blockId, caption: caption)
                        },
                        onOpenViewer: {
                            MediaPresenters.presentScreenshotViewer(
                                noteId: noteId,
                                screenshots: host.screenshotPayloads()
                            )
                        },
                        onEmbeddedImageAction: { blockId, action in
                            await host.performEmbeddedImageAction(blockId: blockId, action: action)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // FR-100 (T290): Finder drag-drop inserts a file-reference
                // block (references, never copies — FR-102).
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url {
                            Task { @MainActor in
                                await host.insertFileReferenceBlock(url: url)
                            }
                        }
                    }
                    return true
                }
                // FR-091 capture choices (FR-131: permission on invocation).
                .confirmationDialog("Add Screenshot", isPresented: $showCaptureMenu, titleVisibility: .visible) {
                    Button("Capture Region…") {
                        Task { await host.captureRegion() }
                    }
                    Button("Capture Window…") {
                        Task { await host.captureWindow() }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .background(ReadableTheme.background(for: note))
            } else {
                Color.clear
                    .task { await load() }
            }
        }
        .task {
            if let host { await host.load() }
        }
    }

    private func load() async {
        let model = NoteWindowHostModel(noteId: noteId, environment: environment)
        await model.load()
        host = model
    }

    // MARK: - FR-031 upper-area capture + file entries (T293/T290)

    @State private var showCaptureMenu = false

    /// Captures a screenshot (region or window, user choice).
    private func captureScreenshot() {
        guard host != nil else { return }
        showCaptureMenu = true
    }

    /// Picks a file (NSOpenPanel) and inserts a file-reference block.
    private func pickAndInsertFileReference() {
        guard let host else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await host.insertFileReferenceBlock(url: url) }
    }

    // MARK: - FR-031 note-level actions (T282)

    /// Duplicate note: new UUID, byte-identical blocks + appearance, fresh
    /// manual sort key (FR-022a), lifecycle active (T248).
    private func duplicateNote(host: NoteWindowHostModel) {
        guard let note = host.note, let repo = environment.persistence.noteRepository else { return }
        let duplicated = NoteDuplicator.duplicate(host.note ?? note, blocks: host.blocks, deviceId: DeviceIdentity.current.id)
        Task {
            do {
                try await repo.create(duplicated.note)
                for block in duplicated.blocks {
                    try await repo.insert(block)
                }
                await environment.syncCoordinator?.localContentChanged()
            } catch {
                // FR-011a: non-blocking; the library surface owns status text.
            }
        }
    }

    /// Move to Trash (FR-014): closes the open window immediately and
    /// presents the localized FR-009a deletion toast.
    private func moveToTrash(host: NoteWindowHostModel) {
        guard let repo = environment.persistence.noteRepository else { return }
        Task {
            try? await repo.trash(id: noteId, deviceId: DeviceIdentity.current.id)
            await environment.syncCoordinator?.localContentChanged()
            coordinator.closeAll(noteId: noteId)
            coordinator.deletionToast(String(localized: "Moved to Trash"))
        }
    }
}
