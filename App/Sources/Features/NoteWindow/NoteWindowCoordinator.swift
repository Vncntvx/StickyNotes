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
    /// 003 T032: insertion-notification observers (removed in deinit).
    @ObservationIgnored private nonisolated(unsafe) var insertionObserver: NSObjectProtocol?
    @ObservationIgnored private nonisolated(unsafe) var insertionObservers: [NSObjectProtocol] = []
    /// Retains each window's delegate: `NSWindow.delegate` is WEAK, so the
    /// delegate would otherwise deallocate right after `open()` returns and
    /// `windowWillClose` (frame save, FR-141a flush, FR-012a auto-discard)
    /// would never fire. Freed on unregister/close.
    @ObservationIgnored private var windowDelegates: [UUID: NoteWindowDelegate] = [:]
    /// 003 T032: per-window hosts, keyed by noteId — used to dispatch the
    /// Edit/Insert menu commands to the key note window.
    @ObservationIgnored private var hosts: [UUID: NoteWindowHostModel] = [:]

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
        // 003 T032 (SC-004): the Edit/Insert menu commands dispatch block
        // insertion to the KEY note window's host.
        insertionObserver = NotificationCenter.default.addObserver(
            forName: .stickyRequestInsertTodo, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.insertInKeyWindow(kind: .todo) }
        }
        let codeObserver = NotificationCenter.default.addObserver(
            forName: .stickyRequestInsertCode, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.insertInKeyWindow(kind: .code) }
        }
        let fileObserver = NotificationCenter.default.addObserver(
            forName: .stickyRequestInsertFileReference, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.insertFileReferenceInKeyWindow() }
        }
        let captureObserver = NotificationCenter.default.addObserver(
            forName: .stickyRequestCaptureScreenshot, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.captureScreenshotInKeyWindow() }
        }
        insertionObservers = [codeObserver, fileObserver, captureObserver]
    }

    deinit {
        if let displayObserver {
            NotificationCenter.default.removeObserver(displayObserver)
        }
        if let insertionObserver {
            NotificationCenter.default.removeObserver(insertionObserver)
        }
        for observer in insertionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 003 T032 (SC-004): Edit/Insert menu dispatch

    private enum InsertionKind {
        case todo
        case code
    }

    /// Dispatches a block-insertion request to the KEY note window's host
    /// (the Edit/Insert menu commands).
    private func insertInKeyWindow(kind: InsertionKind) {
        guard let (noteId, _) = hosts.first(where: { entry in
            entry.value.noteId == entry.key &&
            NoteWindowBridge.registeredWindow(for: entry.key)?.isKeyWindow == true
        }) else {
            // No key note window — the request targets a key window that is
            // a note window; fall back to the first visible note window.
            guard let any = hosts.keys.first(where: {
                NoteWindowBridge.registeredWindow(for: $0)?.isVisible == true
            }) else { return }
            _ = any
            return
        }
        let host = hosts[noteId]
        switch kind {
        case .todo: Task { _ = await host?.insertTodoBlock() }
        case .code: Task { _ = await host?.insertCodeBlock() }
        }
    }

    private func insertFileReferenceInKeyWindow() {
        guard let host = keyHost() else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await host.insertFileReferenceBlock(url: url) }
    }

    private func captureScreenshotInKeyWindow() {
        guard let host = keyHost() else { return }
        // FR-131: capture permission is requested on invocation; the host
        // presents the region/window capture flow.
        Task { await host.captureRegion() }
    }

    private func keyHost() -> NoteWindowHostModel? {
        if let keyNoteId = hosts.keys.first(where: {
            NoteWindowBridge.registeredWindow(for: $0)?.isKeyWindow == true
        }) {
            return hosts[keyNoteId]
        }
        return hosts.keys.first.flatMap { hosts[$0] }
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // FR-030a (T298): note-paper chrome. The titlebar appears
        // TRANSPARENT and the window background is the OPAQUE note color,
        // so the titlebar area renders as note-colored paper (never a
        // white bar, never see-through) with the traffic lights on it —
        // Apple Sticky Notes style. User decisions 2026-08-09: a standard
        // white titlebar was rejected as ugly; a clear background made the
        // top show the desktop. The TITLE TEXT stays hidden in the
        // titlebar — the editable title field lives in the controls row,
        // and showing it in BOTH places duplicated it (screenshot
        // 2026-08-09).
        window.title = note.title ?? ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = ReadableTheme.windowBackground(for: note)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        // 003 T034 (FR-071): keep the note usable at compact sizes — a
        // minimum content size preserves typing + traffic lights without
        // exposing a full toolbar.
        window.contentMinSize = NSSize(width: 260, height: 200)
        NoteWindowBridge.applyCollectionBehavior(window, alwaysOnTop: note.alwaysOnTop)
        _ = NoteWindowBridge.register(window, noteId: noteId)
        WindowLevelBridge.apply(window, alwaysOnTop: note.alwaysOnTop)

        let host = NoteWindowHostModel(noteId: noteId, environment: environment)
        // 003 T032: retain the host for Edit/Insert menu dispatch.
        hosts[noteId] = host
        let content = NoteWindowContent(noteId: noteId, host: host, environment: environment, coordinator: self)
        // FR-030a: the 8-pt corner radius, 1-pt subtle border and rounded
        // clipping are drawn IN SwiftUI (NoteWindowContent.background) —
        // NOT on the NSHostingView's layer. Verified 2026-08-09: layer
        // corner/border mutations on a hosting view are reset by SwiftUI
        // on macOS 26, leaving a stale square 2-px border that rendered
        // PURE BLACK around new note windows. Layer-BACKING itself is kept
        // (fullSizeContentView compositing needs it for the transparent
        // titlebar — without it the Liquid Glass titlebar material draws
        // a white band over the note paper).
        window.contentView = NSHostingView(rootView: content)
        window.contentView?.wantsLayer = true

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
        windowDelegates[noteId] = delegate

        // FR-007a: the new note window receives keyboard focus immediately.
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        return window
    }

    /// Closes the note's window(s) immediately (FR-009a delete path).
    public func closeAll(noteId: UUID) {
        NoteWindowBridge.registeredWindow(for: noteId)?.close()
        NoteWindowBridge.unregister(noteId: noteId)
        windowDelegates[noteId] = nil
        hosts[noteId] = nil
    }

    /// Whether a note window is currently open.
    public func isOpen(noteId: UUID) -> Bool {
        NoteWindowBridge.isOpen(noteId: noteId)
    }

    /// Re-applies the note color to the window background when the note's
    /// appearance changes while open (the titlebar shows this color, so
    /// the paper stays continuous — FR-030a).
    public func updateNotePaper(noteId: UUID) {
        guard let note = hosts[noteId]?.note,
              let window = NoteWindowBridge.registeredWindow(for: noteId) else { return }
        window.backgroundColor = ReadableTheme.windowBackground(for: note)
    }

    /// Re-applies the Always-on-Top state when the note's pin is toggled
    /// while open (FR-036). Level + collection behavior (`.fullScreenAuxiliary`)
    /// are otherwise only set at window creation. Ordering is one-way:
    /// pinning lifts the window to the front of the floating level;
    /// unpinning only drops the LEVEL — the window keeps its z-position
    /// and naturally falls behind other windows as they come forward
    /// (verified 2026-08-09: orderBack on unpin sank an active window
    /// behind every normal window — bad UX).
    public func updateAlwaysOnTop(noteId: UUID) {
        guard let note = hosts[noteId]?.note,
              let window = NoteWindowBridge.registeredWindow(for: noteId) else { return }
        WindowLevelBridge.apply(window, alwaysOnTop: note.alwaysOnTop)
        NoteWindowBridge.applyCollectionBehavior(window, alwaysOnTop: note.alwaysOnTop)
        if note.alwaysOnTop {
            window.orderFrontRegardless()
        }
    }

    /// Frees the retained window delegate (called from windowWillClose and
    /// the FR-009a delete path).
    public func releaseWindowDelegate(noteId: UUID) {
        windowDelegates[noteId] = nil
        hosts[noteId] = nil
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
        // Release the retained delegate (see windowDelegates — NSWindow's
        // delegate reference is weak; the coordinator holds it).
        coordinator?.releaseWindowDelegate(noteId: noteId)
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
                            coordinator.updateNotePaper(noteId: noteId)
                            coordinator.updateAlwaysOnTop(noteId: noteId)
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
                            // T297: the viewer loads REAL asset bytes via
                            // the composed AssetStore (thumbnail <100% zoom,
                            // original ≥100%) and deletes the association
                            // through the host (FR-094b cover nullification
                            // at the persistence layer).
                            MediaPresenters.presentScreenshotViewer(
                                noteId: noteId,
                                screenshots: host.screenshotPayloads(),
                                imageProvider: { assetId in
                                    try? await environment.assets.store?.readData(assetID: assetId)
                                },
                                onDeleteAssociation: { originalAssetId in
                                    Task { await host.deleteScreenshotBlock(originalAssetId: originalAssetId) }
                                }
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
                // FR-030a (T298): note-paper chrome in SwiftUI — 8-pt
                // rounded background + 1-pt subtle border + rounded
                // clipping (replaces the former NSHostingView layer
                // mutation, which macOS 26 resets and rendered as a black
                // square ring — verified 2026-08-09).
                .notePaperBackground(for: note)
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
        // CRITICAL (verified 2026-08-09): load into the EXISTING host.
        // Creating a new model here replaced the view's @State host with a
        // second instance — the coordinator's `hosts[noteId]` kept the
        // original, and every edit (e.g. the Always-on-Top toggle) updated
        // the view's host while the coordinator read the stale one (the
        // pin never took effect / never released).
        if let host {
            await host.load()
        } else {
            let model = NoteWindowHostModel(noteId: noteId, environment: environment)
            await model.load()
            host = model
        }
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

/// FR-030a: note-paper chrome — 8-pt rounded background and rounded
/// clipping, drawn in SwiftUI so colors resolve per appearance. NO stroke
/// is drawn here: the window's native frame already supplies the hairline
/// edge (Liquid Glass), and the former NSHostingView layer border was
/// reset by SwiftUI on macOS 26 and rendered as a stale square black ring
/// (verified 2026-08-09). A SwiftUI stroke on top produced a doubled
/// 2-line edge (screenshot 2026-08-09), so the border stays native.
private extension View {
    func notePaperBackground(for note: Note) -> some View {
        background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(ReadableTheme.background(for: note))
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
