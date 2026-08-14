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
    /// 004 T016 (FR-006): per-window toolbar controllers (AppKit NSToolbar
    /// lifecycle objects — created with the window, released with the
    /// delegate, mirroring `windowDelegates`).
    @ObservationIgnored private var toolbars: [UUID: NoteToolbarController] = [:]

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
        guard let host = hosts[noteId] else { return }
        // 004 修复 (2026-08-13 用户实测): the menu commands previously
        // passed NO target → every insertion degraded to `.append`, landing
        // at the note's end (错位) and leaving trailing empty paragraphs as
        // a phantom gap. Resolve the caret context exactly like the toolbar.
        let target = insertionTarget(for: host)
        switch kind {
        case .todo: Task { _ = await host.insertTodoBlock(target: target) }
        case .code: Task { _ = await host.insertCodeBlock(target: target) }
        }
    }

    /// 004 US4 (FR-010): the key window's insertion target — the editor's
    /// caret/focus context, degraded to `.append` when stale.
    private func insertionTarget(for host: NoteWindowHostModel) -> InsertionTarget {
        let context = EditorSelectionContext.current(for: host.noteId)
        return NoteWindowDerivations.resolveInsertionTarget(blocks: host.blocks, context: context)
    }

    private func insertFileReferenceInKeyWindow() {
        guard let host = keyHost() else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = insertionTarget(for: host)
        Task { await host.insertFileReferenceBlock(url: url, target: target) }
    }

    private func captureScreenshotInKeyWindow() {
        guard let host = keyHost() else { return }
        // FR-131: capture permission is requested on invocation; the host
        // presents the region/window capture flow.
        let target = insertionTarget(for: host)
        Task { await host.captureRegion(target: target) }
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 004 (T012, FR-001/FR-002): standard macOS titlebar + system
        // window toolbar as the ONLY top-level chrome. `.fullSizeContentView`
        // extends the note paper under the titlebar (single content layer —
        // FR-018); the titlebar stays transparent so the note color + its
        // transparency (T014) render continuously behind the system glass.
        // The former FR-030a black-bar regression is gone: the window
        // background and the SwiftUI paper layer compose the same color.
        // 004 T058 (Q7, Apple Notes title pattern): window.title stays
        // derived (Mission Control / window menus / VoiceOver), but the
        // titlebar renders NO title text — the in-content first line is
        // the single visible, editable title.
        window.title = NoteWindowDerivations.deriveWindowTitle(
            noteTitle: note.title,
            firstLine: NoteWindowDerivations.firstMeaningfulLine(blocks: [])
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = ReadableTheme.windowBackground(for: note)
        window.isReleasedWhenClosed = false
        window.hasShadow = true
        // 004 T058 (FR-017a/Q6): 320pt is the AppKit-enforced real minimum
        // width (2026-08-13 decision — a beautiful conventional minimum;
        // long titles truncate in the content title line, not the chrome).
        // Set AFTER the toolbar is attached (a toolbar momentarily
        // overrides min-size with its own defaults; FR-017a wins).
        NoteWindowBridge.applyCollectionBehavior(window, alwaysOnTop: note.alwaysOnTop)
        _ = NoteWindowBridge.register(window, noteId: noteId)
        WindowLevelBridge.apply(window, alwaysOnTop: note.alwaysOnTop)

        let host = NoteWindowHostModel(noteId: noteId, environment: environment)
        // 003 T032: retain the host for Edit/Insert menu dispatch.
        hosts[noteId] = host
        // 004 T016: toolbar controller + system toolbar (before the content
        // is hosted so the first layout pass sees the toolbar).
        let toolbarController = NoteToolbarController(noteId: noteId, host: host, coordinator: self)
        toolbars[noteId] = toolbarController
        window.toolbar = toolbarController.toolbar
        toolbarController.syncState()
        // FR-017a/Q6: enforced AFTER the toolbar attach (AppKit resets the
        // min size to its toolbar-derived default during attachment).
        window.contentMinSize = NSSize(width: 320, height: 140)
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

        // FR-032/FR-033 (T289): restore the remembered frame BEFORE the
        // window is shown. The repository fetch is async — the previous
        // fire-and-forget Task applied the frame AFTER `makeKeyAndOrderFront`,
        // so the window flashed at the default (200,200) slot and then
        // jumped to the remembered position (verified 2026-08-09).
        if let restored = await restoredFrame(for: noteId) {
            window.setFrame(restored, display: false)
        }

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
        // FR-017a/Q6 (verified pattern 2026-08-10): the SwiftUI hosting
        // view propagates its intrinsic minimum (ScrollView → ~0) during
        // the first layout pass, overriding the min set earlier. Force that
        // pass, then enforce the real 320×140 minimum synchronously; the
        // delegate re-asserts it after user resizes.
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentMinSize = NSSize(width: 320, height: 140)
        return window
    }

    /// Closes the note's window(s) immediately (FR-009a delete path).
    public func closeAll(noteId: UUID) {
        NoteWindowBridge.registeredWindow(for: noteId)?.close()
        NoteWindowBridge.unregister(noteId: noteId)
        windowDelegates[noteId] = nil
        hosts[noteId] = nil
        toolbars[noteId]?.teardown()
        toolbars[noteId] = nil
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
        // 004 T015 (contracts §1): the toolbar controller lives and dies
        // with the delegate — released on the same path (its popover is
        // closed, its observation loop cancelled).
        toolbars[noteId]?.teardown()
        toolbars[noteId] = nil
    }

    // MARK: - 004 (T013, FR-003): window title

    /// Pushes the derived window title (manual title → first content line →
    /// localized fallback) from the host to `window.title`. host→window
    /// only (FR-003; the titlebar never writes back).
    public func updateWindowTitle(noteId: UUID) {
        guard let host = hosts[noteId],
              let window = NoteWindowBridge.registeredWindow(for: noteId) else { return }
        window.title = NoteWindowDerivations.deriveWindowTitle(
            noteTitle: host.note?.title,
            firstLine: NoteWindowDerivations.firstMeaningfulLine(blocks: host.blocks)
        )
    }

    // MARK: - 004 (FR-011): note-level actions shared by the toolbar More
    // menu and the content context menu (single implementation, multiple
    // presentations).

    /// Duplicates the note (FR-022a) — same behavior as the former
    /// NoteControlsView action.
    public func duplicateNote(noteId: UUID) {
        guard let host = hosts[noteId],
              let note = host.note,
              let repo = environment.persistence.noteRepository else { return }
        let duplicated = NoteDuplicator.duplicate(note, blocks: host.blocks, deviceId: DeviceIdentity.current.id)
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

    /// Copies the note as Markdown to the pasteboard (FR-031 semantics).
    public func copyNoteAsMarkdown(noteId: UUID) {
        guard let host = hosts[noteId], let note = host.note else { return }
        NoteExportImport.copyNoteAsMarkdown(note: note, blocks: host.blocks)
    }

    /// Exports the note as JSON (FR-031 semantics).
    public func exportNoteAsJSON(noteId: UUID) {
        guard let host = hosts[noteId], let note = host.note else { return }
        _ = NoteExportImport.exportNoteAsJSON(note: note, blocks: host.blocks)
    }

    /// Moves the note to Trash (FR-014): closes the open window immediately
    /// and presents the localized FR-009a deletion toast.
    public func moveToTrash(noteId: UUID) {
        guard let repo = environment.persistence.noteRepository else { return }
        Task {
            try? await repo.trash(id: noteId, deviceId: DeviceIdentity.current.id)
            await environment.syncCoordinator?.localContentChanged()
            closeAll(noteId: noteId)
            deletionToast(String(localized: "Moved to Trash"))
        }
    }

    /// The key note window's host (menu command dispatch — 003 T032).
    public func keyHost() -> NoteWindowHostModel? {
        if let keyNoteId = hosts.keys.first(where: {
            NoteWindowBridge.registeredWindow(for: $0)?.isKeyWindow == true
        }) {
            return hosts[keyNoteId]
        }
        return hosts.keys.first.flatMap { hosts[$0] }
    }

    /// 004 T021 (FR-007/FR-026): View menu "Always on Top" — toggles the
    /// KEY note window's pin through the single entry point.
    public func toggleAlwaysOnTopInKeyWindow() {
        guard let noteId = hosts.keys.first(where: {
            NoteWindowBridge.registeredWindow(for: $0)?.isKeyWindow == true
        }) else { return }
        toggleAlwaysOnTop(noteId: noteId)
    }

    /// Toggles the pin of a note (host persists, coordinator applies the
    /// window behavior).
    public func toggleAlwaysOnTop(noteId: UUID) {
        guard let host = hosts[noteId], var note = host.note else { return }
        note.alwaysOnTop.toggle()
        host.updateAppearance(note)
        updateAlwaysOnTop(noteId: noteId)
    }

    /// 004 T040 (FR-012): Format menu commands — applies marks to the key
    /// window's ACTIVE editor (NSTextView is the authority).
    public func applyMarksInKeyWindow(_ marks: Set<RichTextMark>) {
        let noteIds = Array(hosts.keys)
        guard let bridge = EditorSelectionContext.bridge(forKeyWindow: noteIds) else { return }
        bridge.applyMarks(marks)
    }

    /// 004 T040 (FR-043a): Format menu text-size — whole-note size.
    public func setTextSizeInKeyWindow(_ size: Int) {
        guard let host = keyHost(), var note = host.note else { return }
        note.textSize = NoteAppearance.TextSizeBounds.clamped(size)
        host.updateAppearance(note)
    }

    // MARK: - FR-032/FR-033 window frames (T289)

    /// Restores the note's remembered frame, corrected for the current
    /// display arrangement (FR-032/FR-033).
    /// The remembered window frame, corrected for the current display
    /// arrangement (FR-032/FR-033). Returns nil when no usable state
    /// exists (the caller keeps the default frame). The disconnected-
    /// display preferred frame is preserved untouched.
    private func restoredFrame(for noteId: UUID) async -> NSRect? {
        guard let repo = environment.persistence.windowStateRepository else { return nil }
        guard let state = try? await repo.fetch(noteId: noteId),
              state.frame.width > 0, state.frame.height > 0 else { return nil }
        let displays = DisplayObservation.currentDisplayFrames()
        let preferred = NSRect(x: state.frame.x, y: state.frame.y, width: state.frame.width, height: state.frame.height)
        let fallback = state.fallbackFrame.map { NSRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
        return DisplayChangeBridge.correctedFrame(
            frame: preferred,
            preferredDisplayUUID: state.preferredDisplayUUID,
            fallbackFrame: fallback,
            displays: displays
        )
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
        // FR-017a (004 T058, Q6): re-assert the enforced minimum after any
        // layout-driven change (SwiftUI may re-propagate its intrinsic min).
        if let window = notification.object as? NSWindow {
            window.contentMinSize = NSSize(width: 320, height: 140)
        }
    }

    func windowWillClose(_ notification: Notification) {
        saveFrame(from: notification)
        // 004 T015 (contracts §7): EVERY close path (traffic light, ⌘W,
        // closeAll, menu) must unregister — otherwise `focusExisting`
        // revives the dead host window and pin/appearance/menu dispatch
        // silently stop working. Aligned with the ⌘W path.
        NoteWindowBridge.unregister(noteId: noteId)
        // Release the retained delegate + toolbar controller (see
        // windowDelegates — NSWindow's delegate reference is weak; the
        // coordinator holds it).
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
                // Phase 3: compute the resolved typography VALUE from the
                // observable global preferences + the note's per-note text
                // size. Reading `environment.typography` here registers
                // SwiftUI observation — a preference change re-renders this
                // body, recomputes the value, and every open editor
                // restyles in place.
                let editorTypography = EditorTypography(
                    fontPreference: environment.typography.fontPreference,
                    textSpacing: environment.typography.textSpacing,
                    textSize: ReadableTheme.textSize(for: note)
                )
                VStack(spacing: 0) {
                    RichTextBlockView(
                        note: note,
                        editorTypography: editorTypography,
                        blocks: host.blocks,
                        onAppearanceChange: { updated in
                            host.updateAppearance(updated)
                        },
                        onBlocksChanged: { newBlocks in
                            host.updateBlocks(newBlocks)
                        },
                        onStructuralBlocksChanged: { newBlocks in
                            // 004 修复: editor-side structural changes (e.g.
                            // FR-050a empty-block removal) register ONE undo
                            // group through the host.
                            host.updateBlocksStructural(newBlocks)
                        },
                        onInsertTodo: {
                            Task { await host.insertTodoBlock(target: toolbarInsertionTarget()) }
                        },
                        onInsertCode: {
                            Task { await host.insertCodeBlock(target: toolbarInsertionTarget()) }
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
                        onEmptyTodoExit: { blockId in
                            // FR-050a: the emptied todo merges away on
                            // cursor exit — host-side so the TodoItem row
                            // round-trips with the block in one undo group.
                            await host.removeEmptiedTodoBlock(blockId: blockId)
                        },
                        onDeleteEmptyBlockKey: { blockId in
                            // 2026-08-14 (Q2-A/Q3-B): DELETE key on an empty
                            // block — host-side removal + focus to the next
                            // block's start.
                            await host.deleteEmptyBlockOnKey(blockId: blockId)
                        },
                        onMergeBlock: { blockId in
                            // 2026-08-14 (Q4-A): first-character Backspace —
                            // merge the block's text into its predecessor.
                            await host.mergeBlockIntoPrevious(blockId: blockId)
                        },
                        onInsertParagraphAfterBlock: { blockId in
                            // 2026-08-14 (Q5-A/Q6-B): todo-tail Return —
                            // materialize an empty paragraph right after the
                            // todo (between consecutive todos).
                            await host.insertRichTextBlock(target: .afterBlock(blockId: blockId))
                        },
                        onDeleteSpanningSelection: { selection in
                            // 2026-08-14: 跨块模式下 Backspace/Delete — host
                            // 跨块删除（单 undo 组 + 焦点末块）。
                            await host.applySpanningDeletion(selection: selection)
                        },
                        onDeleteCode: { blockId in
                            // 004 修复 (第二轮): the code block's hover-menu
                            // Delete — host-side structural deletion (ONE
                            // undo group re-inserts it on ⌘Z, FR-141a
                            // immediate persist).
                            await host.deleteBlock(id: blockId)
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
                        },
                        // 004 修复: unified editing context — every block
                        // editor shares the window-level UndoManager; a
                        // fresh insert focuses the new block; todo rows
                        // re-fetch their state on structural undo/redo.
                        undoManager: host.undoManager,
                        focusRequest: host.pendingFocusRequest,
                        onFocusRequestHandled: {
                            host.clearPendingFocusRequest()
                        },
                        onContinueDocument: {
                            // 004 修复 (2026-08-14, P0): the document tail
                            // was clicked — focus the trailing paragraph or
                            // materialize a new one after the last block.
                            Task { await host.continueDocument() }
                        },
                        todoRevision: host.undoRevision
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // 004 T013 (FR-003): the window title follows the host —
                // host→window only, on title edits and on block changes
                // (first-line derivation).
                .onChange(of: host.note?.title) {
                    coordinator.updateWindowTitle(noteId: noteId)
                }
                .onChange(of: host.blocks) {
                    coordinator.updateWindowTitle(noteId: noteId)
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
                        Task { await host.captureRegion(target: toolbarInsertionTarget()) }
                    }
                    Button("Capture Window…") {
                        Task { await host.captureWindow(target: toolbarInsertionTarget()) }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                // 004 T018 (FR-029): ⌥C/⌥O/⌥T stepping shortcuts migrated
                // from the removed NoteControlsView (keys + behavior
                // unchanged).
                .overlay(alignment: .topLeading) {
                    shortcutOverlay
                }
                // 004 T019 (FR-031): note-level actions live on the content
                // area's context menu (duplicate/copy/export/trash +
                // appearance) — the toolbar More menu presents the
                // SAME actions.
                .contextMenu {
                    noteContextMenu
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
            // 004 修复 (2026-08-13): only load when the host has no data —
            // a late re-load re-fetches the DB and clobbers in-memory
            // blocks (e.g. a just-inserted todo) and the undo context.
            if let host, host.note == nil { await host.load() }
        }
    }

    // MARK: - 004 T018 (FR-029): ⌥C/⌥O/⌥T keyboard stepping (migrated)

    @ViewBuilder
    private var shortcutOverlay: some View {
        HStack(spacing: 0) {
            Button("") { cycleNextColor() }
                .keyboardShortcut("c", modifiers: .option)
            Button("") { cycleNextOpacity() }
                .keyboardShortcut("o", modifiers: .option)
            Button("") { cycleNextTextSize() }
                .keyboardShortcut("t", modifiers: .option)
        }
        .hidden()
        .accessibilityHidden(true)
    }

    /// ⌥C: steps to the next palette color (wraps).
    private func cycleNextColor() {
        guard let host, var note = host.note else { return }
        let colors = NotePaletteKey.allCases
        let currentKey = NoteWindowDerivations.paletteKey(for: note) ?? .yellow
        guard let current = colors.firstIndex(of: currentKey) else {
            note = NoteWindowDerivations.note(applyingPaletteKey: colors[0], to: note)
            host.updateAppearance(note)
            return
        }
        note = NoteWindowDerivations.note(applyingPaletteKey: colors[(current + 1) % colors.count], to: note)
        host.updateAppearance(note)
        coordinator.updateNotePaper(noteId: noteId)
    }

    /// ⌥O: steps to the next opacity step (wraps).
    private func cycleNextOpacity() {
        guard let host, var note = host.note else { return }
        let steps = NoteAppearance.OpacityBounds.allSteps
        guard let current = steps.firstIndex(of: note.transparency) else {
            note.transparency = steps[0]
            host.updateAppearance(note)
            return
        }
        note.transparency = steps[(current + 1) % steps.count]
        host.updateAppearance(note)
        coordinator.updateNotePaper(noteId: noteId)
    }

    /// ⌥T: steps to the next text size (wraps).
    private func cycleNextTextSize() {
        guard let host, var note = host.note else { return }
        let sizes = NoteAppearance.TextSizeBounds.allSizes
        guard let current = sizes.firstIndex(of: note.textSize) else {
            note.textSize = sizes[0]
            host.updateAppearance(note)
            return
        }
        note.textSize = sizes[(current + 1) % sizes.count]
        host.updateAppearance(note)
    }

    // MARK: - 004 T019 (FR-031): content-area context menu

    @ViewBuilder
    private var noteContextMenu: some View {
        Button("Duplicate Note") { coordinator.duplicateNote(noteId: noteId) }
        Button("Copy as Markdown") { coordinator.copyNoteAsMarkdown(noteId: noteId) }
        Divider()
        Button("Export as JSON…") { coordinator.exportNoteAsJSON(noteId: noteId) }
        Button("Move to Trash") { coordinator.moveToTrash(noteId: noteId) }
        Divider()
        // T301 (FR-181): full-value appearance submenus — every color /
        // opacity step / text size reachable without pointer hover (moved
        // from the removed NoteControlsView).
        Menu("Note Appearance") {
            Menu("Note Color") {
                ForEach(NotePaletteKey.allCases, id: \.self) { key in
                    Button {
                        applyPalette(key)
                    } label: {
                        HStack {
                            Circle()
                                .fill(NotePalette.dynamicColor(for: key))
                                .frame(width: 10, height: 10)
                            Text(NotePalette.displayName(for: key))
                        }
                    }
                }
            }
            Menu("Background Opacity") {
                ForEach(NoteAppearance.OpacityBounds.allSteps, id: \.self) { step in
                    Button(NoteWindowDerivations.formatOpacityPercent(step)) {
                        applyOpacity(step)
                    }
                }
            }
            Menu("Text Size") {
                ForEach(NoteAppearance.TextSizeBounds.allSizes, id: \.self) { size in
                    Button("\(size) pt") {
                        applyTextSize(size)
                    }
                }
            }
        }
        Divider()
    }

    private func applyPalette(_ key: NotePaletteKey) {
        guard let host, let note = host.note else { return }
        host.updateAppearance(NoteWindowDerivations.note(applyingPaletteKey: key, to: note))
        coordinator.updateNotePaper(noteId: noteId)
    }

    private func applyOpacity(_ step: Double) {
        guard let host, var note = host.note else { return }
        note.transparency = step
        host.updateAppearance(note)
        coordinator.updateNotePaper(noteId: noteId)
    }

    private func applyTextSize(_ size: Int) {
        guard let host, var note = host.note else { return }
        note.textSize = size
        host.updateAppearance(note)
    }

    /// 004 US4: the current insertion target (editor caret/focus context
    /// via the selection bridge; degraded to `.append`).
    private func toolbarInsertionTarget() -> InsertionTarget? {
        guard let host else { return nil }
        let context = EditorSelectionContext.current(for: noteId)
        return NoteWindowDerivations.resolveInsertionTarget(blocks: host.blocks, context: context)
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
        let target = toolbarInsertionTarget()
        Task { await host.insertFileReferenceBlock(url: url, target: target) }
    }
}

/// FR-030a: note-paper chrome — 8-pt rounded clipping, drawn in SwiftUI.
/// The note surface color comes from the WINDOW background (T072 — single
/// source, no double alpha). NO stroke is drawn here: the window's native
/// frame already supplies the hairline edge (Liquid Glass), and the former
/// NSHostingView layer border was reset by SwiftUI on macOS 26 and rendered
/// as a stale square black ring (verified 2026-08-09). A SwiftUI stroke on
/// top produced a doubled 2-line edge (screenshot 2026-08-09), so the
/// border stays native.
private extension View {
    func notePaperBackground(for note: Note) -> some View {
        // 004 T072 (2026-08-13): NO paper fill — the WINDOW background
        // (`ReadableTheme.windowBackground`, note color × transparency) is
        // the single source of the note surface. A second color×alpha fill
        // here double-applied the transparency: the paper composited to
        // ~1-(1-a)² and looked visibly MORE opaque than the titlebar strip
        // (user report: strip vs paper transparency mismatch). The rounded
        // clip stays for FR-030a content clipping.
        clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
