import SwiftUI
import AppKit
import Domain
import EditorCore

// MARK: - EditorDisplayStyling (004 修复, 2026-08-13)
//
// Display-only styling for a block editor (todo completion): applied over
// the full text range and EXCLUDED from the canonical round trip — a
// completed todo's strikethrough/secondary color is presentation, not a
// model mark (FR-053 marks stay untouched).

/// Display-only styling applied by an editor's host (todo completion state).
public struct EditorDisplayStyling: Equatable, Sendable {
    public var strikethrough: Bool
    public var secondaryColor: Bool

    public init(strikethrough: Bool = false, secondaryColor: Bool = false) {
        self.strikethrough = strikethrough
        self.secondaryColor = secondaryColor
    }
}

// MARK: - RichTextView (verified 2026-08-07)
//
// SwiftUI `TextEditor` fallback — the plan-sanctioned path:
//
//   "if Phase 0 proves SwiftUI `TextEditor` cannot reliably satisfy a
//    required behavior, an isolated `NSViewRepresentable` around `NSTextView`
//    for the rich-text block ONLY is permitted, documented as an
//    architecture decision, behind a protocol, canonical format unchanged"
//    (plan.md §Editor architecture).
//
// Verified on macOS 27 beta (26A5388g): `TextEditor`'s AttributedString
// binding NEVER writes back — neither the synthesized binding nor an
// explicit `Binding` `set` fires while typing (display updates, binding
// does not). Typed input was therefore lost entirely. `NSTextView`'s
// delegate callbacks fire reliably, so the canonical document round-trips
// through AppKit.
//
// Constraints honored:
// - FR-053: only application-supported attributes (bold/italic/underline/
//   strike/inline-code/link) survive the round trip; everything else is
//   dropped when building the canonical document.
// - FR-063: commits are suppressed while marked text (IME composition) is
//   active (`hasMarkedText`), so partial composition never enters storage.
// - FR-141a: the App layer debounces persistence; this view only reports
//   canonical documents.
// - Plan §Module boundaries: AppKit stays in the App layer; Domain/
//   EditorCore types are the only thing crossing the boundary.

/// An NSTextView-backed rich-text editor for a note's primary block.
public struct RichTextView: NSViewRepresentable {
    // MARK: Alignment metrics (004 T061, SC-004)
    //
    // The body's text left origin MUST sit on the SAME line as the title
    // field's left edge (Apple Notes pattern — title and body share one
    // left edge; 2026-08-13 user feedback). Horizontal insets are ZERO:
    // the paper's horizontal padding lives in the SwiftUI container
    // (RichTextBlockView `.padding(.horizontal, inset)`), which applies to
    // title and body alike. Vertical inset stays for first-line breathing.
    public static let textContainerHorizontalInset: CGFloat = 0
    public static let lineFragmentPadding: CGFloat = 0
    public static let textContainerVerticalInset: CGFloat = 12

    /// The canonical document currently owned by the model.
    let document: RichTextDocument
    /// The resolved typography for this editor (Phase 2, 2026-08-14): the
    /// global font preference (nil = system font), the spacing preset, and
    /// the PER-NOTE text size. A required VALUE — the SwiftUI layer computes
    /// it from the observable `TypographyPreferences`; the editor subtree
    /// never touches UserDefaults or the preference object.
    let editorTypography: EditorTypography
    /// Reports a canonical document produced by editing (only supported
    /// attributes survive — FR-053).
    let onCommit: (RichTextDocument) -> Void
    /// Reports focus changes with the IME marked-text state (FR-050a
    /// removal must not fire during composition — FR-063).
    let onFocusChange: (Bool, Bool) -> Void
    /// 004 T037 (FR-012): the note's selection bridge (published into by
    /// this editor's Coordinator).
    let selectionBridge: EditorSelectionBridge?
    /// 004 T037: the block id backing this editor (insertion-target
    /// resolution).
    let richTextBlockId: UUID?
    /// 004 修复: the window-level shared UndoManager — every block editor
    /// (primary/trailing/todo) uses it so ⌘Z/⌘⇧Z span the whole note.
    let undoManager: UndoManager?
    /// 004 修复: the editor's minimum height — the primary paper keeps the
    /// 320pt minimum; trailing/todo editors pass 0 (content-sized, so an
    /// inserted block no longer renders a second 320pt paper).
    let minimumHeight: CGFloat?
    /// 004 修复 (2026-08-13 用户实测第二轮): the text-container VERTICAL
    /// inset. The primary paper keeps 12pt (first-line breathing room
    /// under the controls row); secondary editors (trailing split blocks,
    /// todo text) pass 0 — the block-stack spacing owns their rhythm, an
    /// inset would double it (34pt between blocks read as 大段间隔).
    let verticalInset: CGFloat
    /// 004 修复 (2026-08-13 用户实测第二轮): collapse the paper's BOTTOM
    /// inset once blocks follow it (NotePaperTextView.collapsesBottomInset)
    /// — the dead paper under the last ink line disappears.
    let collapsesBottomInset: Bool
    /// 004 修复: special-block editor (todo text) — publishes its
    /// focusedSpecialBlockId so insertion targets `.afterBlock` (FR-010).
    let isSpecialBlock: Bool
    /// 004 修复: display-only styling (todo completion strikethrough +
    /// secondary color) — applied visually, excluded from the canonical
    /// round trip.
    let displayStyling: EditorDisplayStyling?
    /// 004 修复 (2026-08-14, P1): publishes the FIRST LINE's typographic
    /// center (line-fragment midY in view coordinates — real TextKit
    /// geometry, not nominal font metrics) — the todo row's marker
    /// visual center aligns to it.
    let onFirstLineTypographicCenter: ((CGFloat) -> Void)?
    /// 004 修复: insertion-focus request — this editor becomes first
    /// responder (caret at `caretAtEnd ? end : start`) once it lands in a
    /// window.
    let requestFocus: Bool
    /// 004 修复 (2026-08-14, P0): where the caret lands on a focus request
    /// — `.end` resumes typing at the tail of an existing paragraph (tail
    /// continuation), `.start` is the insertion default.
    let caretAtEnd: Bool
    let onFocusRequestHandled: () -> Void

    public init(
        document: RichTextDocument,
        editorTypography: EditorTypography,
        onCommit: @escaping (RichTextDocument) -> Void,
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in },
        selectionBridge: EditorSelectionBridge? = nil,
        richTextBlockId: UUID? = nil,
        undoManager: UndoManager? = nil,
        minimumHeight: CGFloat? = nil,
        verticalInset: CGFloat = RichTextView.textContainerVerticalInset,
        collapsesBottomInset: Bool = false,
        isSpecialBlock: Bool = false,
        displayStyling: EditorDisplayStyling? = nil,
        onFirstLineTypographicCenter: ((CGFloat) -> Void)? = nil,
        requestFocus: Bool = false,
        caretAtEnd: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {}
    ) {
        self.document = document
        self.editorTypography = editorTypography
        self.onCommit = onCommit
        self.onFocusChange = onFocusChange
        self.selectionBridge = selectionBridge
        self.richTextBlockId = richTextBlockId
        self.undoManager = undoManager
        self.minimumHeight = minimumHeight
        self.verticalInset = verticalInset
        self.collapsesBottomInset = collapsesBottomInset
        self.isSpecialBlock = isSpecialBlock
        self.displayStyling = displayStyling
        self.onFirstLineTypographicCenter = onFirstLineTypographicCenter
        self.requestFocus = requestFocus
        self.caretAtEnd = caretAtEnd
        self.onFocusRequestHandled = onFocusRequestHandled
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = NotePaperTextView()
        textView.isRichText = true
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = true
        // Text insets are the NSTextView-native way to give the paper's
        // first line breathing room under the controls row: the inset is
        // part of the text view's intrinsic size, so it always applies
        // (unlike SwiftUI container padding, which ScrollView layout can
        // eat — verified 2026-08-09: a 24pt SwiftUI top padding rendered
        // as ~12pt). The caret starts at the inset, so the typing
        // position matches the visual inset.
        // 004 修复 (第二轮): the inset height is per-editor — the primary
        // paper keeps 12pt; secondary editors pass 0 (the block-stack
        // spacing owns their rhythm).
        textView.textContainerInset = NSSize(
            width: Self.textContainerHorizontalInset,
            height: verticalInset
        )
        textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding
        let resolver = NoteFontResolver(preference: editorTypography.fontPreference)
        textView.font = resolver.font(size: editorTypography.textSize, for: "")
        textView.delegate = context.coordinator
        // PR2: the storage's didProcessEditing reports the EXACT character
        // edit range (the typing normalization consumes it) — the
        // coordinator observes the storage here.
        textView.textStorage?.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        // 004 修复: 尾部/todo 编辑器内容自适应（无 320 最小高度）；主纸面
        // 保持 NotePaperTextView 默认值。
        if let minimumHeight {
            textView.minimumHeight = minimumHeight
        }
        textView.collapsesBottomInset = collapsesBottomInset
        context.coordinator.applyDocument(document, typography: editorTypography, to: textView)
        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // 004 修复 (2026-08-13): the coordinator must track the CURRENT
        // struct — SwiftUI never refreshes the parent captured by
        // `makeCoordinator`, so a stale `parent` would commit against
        // pre-insertion `blocks` snapshots (wiping inserted blocks on the
        // next keystroke) and read stale focus/style flags.
        context.coordinator.parent = self
        // 004 修复 (2026-08-13 用户实测): the minimum height must be
        // re-applied on EVERY update — makeNSView runs once per identity,
        // so the primary paper kept its 320pt minimum after blocks were
        // inserted below it (the "huge gap" persisted).
        // 第二轮: the bottom-inset collapse + the vertical inset follow the
        // same discipline — the insertion flips both IN PLACE.
        if let paper = textView as? NotePaperTextView {
            var dirty = false
            if let minimumHeight, paper.minimumHeight != minimumHeight {
                paper.minimumHeight = minimumHeight
                dirty = true
            }
            if paper.collapsesBottomInset != collapsesBottomInset {
                paper.collapsesBottomInset = collapsesBottomInset
                dirty = true
            }
            if dirty {
                paper.invalidateIntrinsicContentSize()
            }
        }
        if textView.textContainerInset.height != verticalInset {
            textView.textContainerInset = NSSize(
                width: Self.textContainerHorizontalInset,
                height: verticalInset
            )
            textView.invalidateIntrinsicContentSize()
            textView.needsDisplay = true
        }
        // 004 T037: keep the bridge attached to the live text view.
        context.coordinator.attach(textView, bridge: selectionBridge, blockId: richTextBlockId)
        // 004 修复 (2026-08-14, P0): a width reflow must republish the
        // selection rect — the contextual format row re-anchors to the
        // real post-resize geometry.
        if let paper = textView as? NotePaperTextView {
            paper.onWidthReflow = { [weak coordinator = context.coordinator] in
                coordinator?.republishSelection()
                coordinator?.publishFirstLineTypographicCenter(textView)
            }
        }
        // The three update paths (Phase 3, 2026-08-14):
        // A. user typing — handled by textDidChange, NOT here (this branch
        //    only guards against pushing while the user edits);
        // B. content push — the document text actually differs: applyDocument
        //    (may rebuild the attributed string; setAttributedString allowed);
        // C. typography-only refresh — text equal but the RESOLVED typography
        //    changed: restyleTypographyInPlace (in-place attribute edits
        //    ONLY — never setAttributedString, never string replacement).
        //
        // FR-063: while the IME is composing, the live string contains the
        // marked text but the model holds the pre-composition version — both
        // B and C are destructive to the composition, so they defer: the
        // content push skips (the commit canonicalizes once the composition
        // lands) and the typography refresh parks on `pendingTypography`
        // (last-write-wins) until the composition commits.
        if textView.hasMarkedText() {
            if editorTypography != context.coordinator.lastAppliedTypography {
                context.coordinator.pendingTypography = editorTypography
            }
        } else if textView.string != document.text {
            context.coordinator.applyDocument(document, typography: editorTypography, to: textView)
        } else if editorTypography != context.coordinator.lastAppliedTypography {
            context.coordinator.restyleTypographyInPlace(editorTypography, document: document, to: textView)
        }
        // 004 修复: 显示专用样式（todo 完成态）每次更新对齐——文本未变也
        // 要跟随勾选状态切换。
        context.coordinator.applyDisplayStyling(to: textView)
        // 004 修复 (2026-08-14, P1): publish the first line's typographic
        // center for the host's marker alignment (todo checkbox). PR1
        // (2026-08-14): runs AFTER the apply/restyle/display-styling
        // mutations — a pre-mutation publish could deliver pre-restyle
        // geometry while the render is post-restyle, and the checkbox then
        // has no guaranteed second publish to converge on (the async @State
        // write only triggers a re-render when the value CHANGES).
        context.coordinator.publishFirstLineTypographicCenter(textView)
        if requestFocus {
            context.coordinator.requestFocusIfNeeded(textView)
        } else if context.coordinator.didHandleFocusRequest {
            // 004 修复 (2026-08-14, P0): re-arm the one-shot flag when the
            // request clears — tail continuation re-focuses the SAME editor
            // on every click, not once per editor identity.
            context.coordinator.didHandleFocusRequest = false
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextView
        /// Plan B (2026-08-14): a cached layout manager for line-height
        /// METRICS ONLY — never attached to a text storage. MainActor-only
        /// access (`regularBodyLineHeightFloor`), matching the class.
        private static let lineHeightMetricsLayoutManager = NSLayoutManager()
        /// Suppresses delegate-driven commits while the model is pushing a
        /// document in (avoid echo loops).
        private var isPushing = false
        /// 004 T037: the live text view + bridge (weak text view — the
        /// bridge must never outlive the editor).
        private weak var liveTextView: NSTextView?
        private weak var liveBridge: EditorSelectionBridge?
        private var liveBlockId: UUID?
        /// 004 修复: insertion-focus requests are handled once per request
        /// edge (re-armed by updateNSView when the request clears).
        var didHandleFocusRequest = false
        /// Phase 3: the typography the storage was last rendered with —
        /// the updateNSView fingerprint that discriminates content pushes
        /// from presentation-only refreshes.
        var lastAppliedTypography: EditorTypography?
        /// Phase 3: a typography change parked while the IME is composing.
        /// Last-write-wins (no queueing) — the composition commit restyles
        /// once.
        var pendingTypography: EditorTypography?
        /// PR2: the last CHARACTER-edit range reported by the storage's
        /// `didProcessEditing` — consumed by the typing normalization at a
        /// safe point (textDidChange after the FR-063 composition guard).
        /// The storage's own `editedRange` report is used verbatim — NEVER
        /// reconstructed from `changeInLength`, which is a delta (negative
        /// for deletions) and not a range length. While the IME composes,
        /// multiple character edits UNION (coalesce) into one pending range
        /// consumed at composition commit — never last-write-wins.
        var pendingCharacterEditRange: NSRange?

        /// 004 FR-012 (clarify 2026-08-10): the window whose key-state
        /// notifications republish the selection snapshot, plus the
        /// observers (removed when the window changes or the coordinator
        /// deallocates).
        private weak var observedWindow: NSWindow?
        private var keyStateObservers: [any NSObjectProtocol] = []

        deinit {
            MainActor.assumeIsolated {
                keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            }
        }

        init(_ parent: RichTextView) {
            self.parent = parent
        }

        /// 004 修复 (2026-08-14, P1): publishes the editor's first-line
        /// typographic center (real TextKit geometry) so the host aligns
        /// its marker (todo checkbox) to it. The alignment font is the
        /// NOMINAL body font of the CURRENT typography (PR1) — the optical
        /// offset is stable across first-character formatting.
        func publishFirstLineTypographicCenter(_ textView: NSTextView) {
            guard let paper = textView as? NotePaperTextView else { return }
            let resolver = NoteFontResolver(preference: parent.editorTypography.fontPreference)
            let alignmentFont = resolver.nominalBodyFont(size: parent.editorTypography.textSize)
            parent.onFirstLineTypographicCenter?(paper.firstLineTypographicCenterFromTop(alignmentFont: alignmentFont))
        }

        /// 004 修复: routes this editor's undo to the window-level shared
        /// UndoManager — typing in ANY block lands on the same stack as
        /// structural changes (⌘Z/⌘⇧Z span the whole note).
        public func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager
        }

        // MARK: - Formatting (semantic marks — commit + undo, 004 修复)

        /// The semantic marks requested for SUBSEQUENT input (the typing
        /// attributes state). The restyle pipeline rebuilds typing
        /// attributes from this set — never from raw typingAttributes —
        /// so display-only styling (completed-todo strikethrough) can
        /// never leak into semantic state.
        private var pendingTypingMarks: Set<RichTextMark> = []

        /// Applies marks through the semantic pipeline: the selection path
        /// toggles semantic marks per segment, re-renders the presentation,
        /// and COMMITS the canonical document — attribute edits never fire
        /// `textDidChange`, so without this commit a ⌘B-then-close loses
        /// the mark. Undo restores SEMANTIC mark segments with the CURRENT
        /// typography (a font change between ⌘B and ⌘Z survives the undo —
        /// presentation is never undo state).
        @discardableResult
        func applyMarks(_ marks: Set<RichTextMark>, to textView: NSTextView) -> Bool {
            guard !isPushing, !textView.hasMarkedText() else { return false }
            guard let storage = textView.textStorage else { return false }
            let range = textView.selectedRange()
            guard range.length > 0 else {
                // Typing path: no content exists yet — no commit, no undo.
                // Empty marks CLEAR the pending typing marks (2026-08-14).
                if marks.isEmpty {
                    pendingTypingMarks.removeAll()
                } else {
                    pendingTypingMarks.formUnion(marks)
                }
                RichTextMarkApplier.renderTypingAttributes(
                    pendingTypingMarks,
                    textView: textView,
                    textSize: parent.editorTypography.textSize
                )
                return true
            }
            let before = RichTextMarkApplier.semanticMarks(in: range, storage: storage)
            let pairs = before.map { segment in
                (
                    range: segment.range,
                    before: segment.marks,
                    // Empty marks = CLEAR formatting (2026-08-14): after is
                    // the empty set, not a no-op symmetric difference.
                    after: marks.isEmpty ? [] : segment.marks.symmetricDifference(marks)
                )
            }
            RichTextMarkApplier.applyMarks(marks, to: textView)
            commitCurrentDocument(from: textView)
            registerFormattingUndo(pairs, textView: textView)
            // 2026-08-14 fix: attribute edits never fire didChangeText —
            // without this the SwiftUI frame keeps the pre-mark intrinsic
            // (the "⌘B 后段落错位、拉宽才恢复" symptom) whenever the
            // mark changes the laid-out line metrics.
            textView.invalidateIntrinsicContentSize()
            return true
        }

        /// Registers one formatting undo action as its OWN group — the
        /// same discipline as the host's structural undo
        /// (`NoteWindowHostModel.registerStructuralUndo`): event grouping
        /// is temporarily suspended so consecutive formatting commands
        /// reverse one at a time, and typing coalescing is unaffected
        /// (the explicit group closes before the next event's typing).
        private func registerFormattingUndo(
            _ pairs: [(range: NSRange, before: Set<RichTextMark>, after: Set<RichTextMark>)],
            textView: NSTextView
        ) {
            guard let undoManager = textView.undoManager else { return }
            let prior = undoManager.groupsByEvent
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreFormattingSegments(pairs, to: textView, restoringBefore: true)
            }
            undoManager.endUndoGrouping()
            undoManager.groupsByEvent = prior
        }

        /// Restores a semantic formatting state (undo/redo counterpart).
        /// Renders each segment's marks with the CURRENT typography, then
        /// re-commits the canonical document and registers the opposite
        /// direction.
        private func restoreFormattingSegments(
            _ pairs: [(range: NSRange, before: Set<RichTextMark>, after: Set<RichTextMark>)],
            to textView: NSTextView,
            restoringBefore: Bool
        ) {
            guard !isPushing, !textView.hasMarkedText(), let storage = textView.textStorage else { return }
            for pair in pairs {
                let wanted = restoringBefore ? pair.before : pair.after
                RichTextMarkApplier.renderSemanticMarks(
                    wanted,
                    in: pair.range,
                    storage: storage,
                    fontResolver: NoteFontResolver(preference: parent.editorTypography.fontPreference),
                    textSize: parent.editorTypography.textSize
                )
            }
            commitCurrentDocument(from: textView)
            textView.undoManager?.registerUndo(withTarget: self) { target in
                target.restoreFormattingSegments(pairs, to: textView, restoringBefore: !restoringBefore)
            }
            // Same discipline as applyMarks: attribute edits need an
            // explicit intrinsic invalidation.
            textView.invalidateIntrinsicContentSize()
        }

        /// Commits the text view's current attributed content into the
        /// canonical document (shared by text edits and formatting-only
        /// edits — attribute changes never fire `textDidChange`). Returns
        /// the committed document (the restyle-after-composition path
        /// renders against it — the parent's document may still be the
        /// pre-composition version).
        @discardableResult
        private func commitCurrentDocument(from textView: NSTextView) -> RichTextDocument {
            let document = Self.canonicalDocument(
                from: textView.attributedString(),
                excludesDisplayStyling: parent.displayStyling?.strikethrough == true
            )
            parent.onCommit(document)
            return document
        }

        /// 004 T037: attaches the selection bridge to this editor's text
        /// view.
        func attach(_ textView: NSTextView, bridge: EditorSelectionBridge?, blockId: UUID?) {
            liveTextView = textView
            liveBridge = bridge
            liveBlockId = blockId
            observeKeyState(of: textView.window)
            if bridge != nil {
                publishSelection(from: textView)
            }
        }

        /// 004 FR-012 (clarify 2026-08-10): republish the selection/focus
        /// snapshot when the editor's window becomes key or resigns key, so
        /// `bridge.hasFocus` tracks `NSWindow.isKeyWindow` — the contextual
        /// format row must hide while the window is inactive and reappear on
        /// reactivation (selection still present).
        private func observeKeyState(of window: NSWindow?) {
            guard window !== observedWindow else { return }
            keyStateObservers.forEach(NotificationCenter.default.removeObserver)
            keyStateObservers.removeAll()
            observedWindow = window
            guard let window else { return }
            let center = NotificationCenter.default
            keyStateObservers.append(center.addObserver(
                forName: NSWindow.didResignKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.republishSelection() })
            keyStateObservers.append(center.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in self?.republishSelection() })
        }

        /// Republishes the current selection/focus snapshot (key-state
        /// notifications + width reflow).
        func republishSelection() {
            guard let textView = liveTextView else { return }
            publishSelection(from: textView)
        }

        /// The CONTENT push path (Phase 3 rename): model → text view. May
        /// rebuild the attributed string (setAttributedString allowed —
        /// this is the only path permitted to). Does not canonicalize, does
        /// not autosave, registers no undo.
        func applyDocument(_ document: RichTextDocument, typography: EditorTypography, to textView: NSTextView) {
            // FR-063: a model push during composition would overwrite the
            // marked text (the model string still holds the pre-composition
            // version) — defer; the commit canonicalizes once the
            // composition lands.
            guard !textView.hasMarkedText() else { return }
            isPushing = true
            defer { isPushing = false }
            // PR2: a model push rebuilds the whole storage — its edits must
            // never feed the typing normalization (the storage delegate
            // also skips pushes; this reset covers any captured residue).
            pendingCharacterEditRange = nil
            // 004 修复: model pushes must not register undo actions AND must
            // not wipe the shared undo stack (clearing is the structural
            // change's job — NoteWindowHostModel).
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            let resolver = NoteFontResolver(preference: typography.fontPreference)
            textView.font = resolver.font(size: typography.textSize, for: document.text)
            textView.string = document.text
            applyRuns(document, typography: typography, to: textView)
            // The content push resets typing attributes — sync the spacing
            // layer explicitly (Relaxed→Default must really REMOVE the
            // style, not just skip adding it).
            if let style = paragraphStyle(for: typography) {
                textView.typingAttributes[.paragraphStyle] = style
            } else {
                textView.typingAttributes[.paragraphStyle] = nil
            }
            applyDisplayStyling(to: textView)
            lastAppliedTypography = typography
            // 2026-08-14 fix (insertion gap): a content push changes the
            // text but NEVER fires didChangeText (verified — neither the
            // `string` setter nor setAttributedString do) — the intrinsic
            // content size stays stale and SwiftUI keeps the pre-push
            // frame. This is the "插入后与正文距离异常变大、拉宽窗口才恢复"
            // mechanism: the caretSplit trims/splits the body, the frame
            // stays at the old (taller) height. The invalidate must be
            // unconditional — the incidental flag-flip invalidation only
            // covered the single-block shape.
            textView.invalidateIntrinsicContentSize()
        }

        /// 004 修复: applies/removes the display-only styling (todo
        /// completion strikethrough + secondary color). Only touches the
        /// attributes on a styling TRANSITION or while completed — an
        /// uncompleted todo's steady state must never strip user-applied
        /// marks (⌘U etc.). These attributes never enter the canonical
        /// round trip (`canonicalDocument(excludesDisplayStyling:)`).
        private var lastAppliedStyling: EditorDisplayStyling?

        func applyDisplayStyling(to textView: NSTextView) {
            guard let styling = parent.displayStyling else {
                lastAppliedStyling = nil
                return
            }
            // 稳态未完成 → 不触碰；完成态每次更新重涂（粘贴/新输入字符
            // 统一完成态样式）。
            guard styling != lastAppliedStyling || styling.strikethrough else { return }
            lastAppliedStyling = styling
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            if styling.strikethrough {
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: full)
                textView.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                storage.removeAttribute(.strikethroughStyle, range: full)
                textView.typingAttributes[.strikethroughStyle] = nil
            }
            if styling.secondaryColor {
                storage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: full)
                textView.typingAttributes[.foregroundColor] = NSColor.secondaryLabelColor
            } else {
                storage.removeAttribute(.foregroundColor, range: full)
                textView.typingAttributes[.foregroundColor] = nil
            }
        }

        /// 004 修复: insertion-focus — makes this editor the first
        /// responder (caret at start, or at the text end for tail
        /// continuation), then reports handled.
        /// The representable can update before the window attaches (the
        /// update pass runs inside layout), so unattached attempts retry
        /// on the next runloop turn (bounded). The retry captures the
        /// struct's closure + the view directly — it must not depend on
        /// the coordinator surviving the async hop.
        private var focusAttempts = 0

        func requestFocusIfNeeded(_ textView: NSTextView) {
            guard parent.requestFocus, !didHandleFocusRequest else { return }
            if let window = textView.window {
                didHandleFocusRequest = true
                window.makeFirstResponder(textView)
                applyFocusCaret(to: textView)
                parent.onFocusRequestHandled()
                return
            }
            focusAttempts += 1
            guard focusAttempts < 500 else { return }
            let handler = parent.onFocusRequestHandled
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let textView else { return }
                if let window = textView.window {
                    self?.didHandleFocusRequest = true
                    window.makeFirstResponder(textView)
                    self?.applyFocusCaret(to: textView)
                    handler()
                } else {
                    self?.requestFocusIfNeeded(textView)
                }
            }
        }

        /// The caret position for a focus request: the text start by
        /// default; the text END for tail continuation (UTF-16 length —
        /// NSRange space).
        private func applyFocusCaret(to textView: NSTextView) {
            let location = parent.caretAtEnd ? (textView.string as NSString).length : 0
            textView.setSelectedRange(NSRange(location: location, length: 0))
        }

        public func textDidChange(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: never persist partial IME composition.
            guard !textView.hasMarkedText() else { return }
            let document = commitCurrentDocument(from: textView)
            // 004 修复 (2026-08-13 用户实测): FR-063 suppresses selection
            // publishes DURING composition — republish after the commit so
            // the insertion-target registry never lags behind the caret
            // (stale offsets made window-level Insert split at the wrong
            // position right after CJK input).
            publishSelection(from: textView)
            // PR2: normalize the just-edited range to the canonical font
            // plan — live typing becomes visually identical to any content
            // push / restyle within the same runloop turn (Invariant 2).
            // Runs only for USER edits (never during pushes — the capture
            // skips isPushing), and never during composition (the guard
            // above; the pending range unions and is consumed at commit).
            normalizeEditedRangeIfNeeded(textView)
            // Phase 3: the composition has landed — apply a typography
            // change parked during composition (last-write-wins).
            if let pending = pendingTypography {
                pendingTypography = nil
                restyleTypographyInPlace(pending, document: document, to: textView)
            }
        }

        // MARK: - PR2 typing normalization (canonical font projection)

        /// The canonical FONT plan for a storage range, resolved from the
        /// CURRENT typography — the same rules as `presentationFontPlan`
        /// (full coverage via `NoteFontResolver.segmentedFonts` + marks),
        /// driven by the storage's own attribute segments instead of the
        /// document's runs. Single font source of truth: live typing,
        /// content push and restyle all land on this plan.
        private func fontPlan(
            in range: NSRange,
            storage: NSTextStorage
        ) -> [(range: NSRange, font: NSFont, obliqueness: Double?)] {
            let resolver = NoteFontResolver(preference: parent.editorTypography.fontPreference)
            let textSize = parent.editorTypography.textSize
            var plan: [(range: NSRange, font: NSFont, obliqueness: Double?)] = []
            storage.enumerateAttributes(in: range, options: []) { attributes, subrange, _ in
                let marks = RichTextMarkApplier.semanticMarks(from: attributes, excludesDisplayStyling: true)
                let subText = (storage.string as NSString).substring(with: subrange)
                var traits: NSFontDescriptor.SymbolicTraits = []
                if marks.contains(.bold) { traits.insert(.bold) }
                if marks.contains(.italic) { traits.insert(.italic) }
                let segments = resolver.segmentedFonts(text: subText, size: textSize, traits: traits)
                var utf16Cursor = subrange.location
                for segment in segments {
                    let length = (segment.segment as NSString).length
                    guard length > 0 else { continue }
                    var font = segment.font
                    if marks.contains(.inlineCode) {
                        font = NSFont.monospacedSystemFont(ofSize: textSize, weight: traits.contains(.bold) ? .bold : .regular)
                    }
                    let obliqueness: Double? = marks.contains(.italic)
                        && !RichTextMarkApplier.hasTrait(.italic, in: font)
                        ? RichTextMarkApplier.synthesizedItalicObliqueness
                        : nil
                    plan.append((NSRange(location: utf16Cursor, length: length), font, obliqueness))
                    utf16Cursor += length
                }
            }
            return plan
        }

        /// Applies the canonical font plan to the pending character-edit
        /// range (extended to its enclosing paragraph — v1 simplification,
        /// line-metric coherence; documented as NOT the final performance
        /// invariant). Attribute-only edits: no textDidChange, no commit,
        /// no undo registration — the canonical round trip derives marks
        /// from traits, which this pass preserves.
        private func normalizeEditedRangeIfNeeded(_ textView: NSTextView) {
            guard let pending = pendingCharacterEditRange else { return }
            pendingCharacterEditRange = nil
            guard let storage = textView.textStorage else { return }
            var effective = pending
            if effective.length == 0 {
                // Pure deletion: the deletion point may have joined two
                // script runs — cover at least one composed character on
                // each side (the paragraph expansion absorbs the rest).
                effective = NSRange(location: max(0, pending.location - 1), length: 2)
            }
            let full = NSRange(location: 0, length: storage.length)
            let clamped = NSIntersectionRange(effective, full)
            guard clamped.length > 0 else { return }
            let paragraphRange = (storage.string as NSString).paragraphRange(for: clamped)
            guard paragraphRange.length > 0 else { return }
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            storage.beginEditing()
            for entry in fontPlan(in: paragraphRange, storage: storage) {
                storage.addAttribute(.font, value: entry.font, range: entry.range)
                if let obliqueness = entry.obliqueness {
                    storage.addAttribute(.obliqueness, value: obliqueness, range: entry.range)
                }
            }
            storage.endEditing()
        }

        public func textDidEndEditing(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            parent.onFocusChange(false, textView.hasMarkedText())
            publishSelection(from: textView, source: "textDidEndEditing")
            // 2026-08-14 (用户实测): focus left the editor — if it does not
            // return within this event turn (format-row actions restore it
            // synchronously), the selection would linger gray in the
            // unfocused block. The bridge already collapses it when focus
            // MOVES to another editor; this covers focus leaving to a
            // NON-editor (title field, toolbar).
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.window?.firstResponder !== textView else { return }
                let location = textView.selectedRange().location
                textView.setSelectedRange(NSRange(
                    location: location == NSNotFound ? 0 : location,
                    length: 0
                ))
            }
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true, false)
            if let textView = notification.object as? NSTextView {
                publishSelection(from: textView, source: "textDidBeginEditing")
            }
        }

        // MARK: - 004 T037 (FR-012): selection observation

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: do not publish selection during IME composition.
            guard !textView.hasMarkedText() else { return }
            publishSelection(from: textView, source: "textViewDidChangeSelection")
        }

        /// Publishes the current selection/focus snapshot into the bridge.
        func publishSelection(from textView: NSTextView, source: String = "?") {
            guard let bridge = liveBridge else { return }
            let range = textView.selectedRange()
            let hasFocus = (textView.window?.isKeyWindow ?? false) && (textView.window?.firstResponder === textView)
            var rect: CGRect?
            if range.length > 0 {
                let screenRect = textView.firstRect(forCharacterRange: range, actualRange: nil)
                rect = textView.window?.convertFromScreen(screenRect) ?? textView.bounds
            }
            // 004 修复: NSTextView 的 range.location 是 UTF-16 码元偏移，
            // canonical 文档与块拆分使用 scalar 偏移 — 转换后发布，否则
            // CJK/emoji 光标处拆分落错位。
            let scalarOffset = NoteWindowDerivations.scalarOffset(fromUTF16: range.location, in: textView.string)
            // 2026-08-14: the selection's semantic marks drive the format
            // bar's active states (toggle buttons highlight when present).
            let marks: Set<RichTextMark>
            if range.length > 0, let storage = textView.textStorage {
                marks = RichTextMarkApplier.semanticMarks(in: range, storage: storage)
                    .reduce(into: Set<RichTextMark>()) { $0.formUnion($1.marks) }
            } else {
                marks = []
            }
            bridge.publish(
                from: textView,
                caretBlockId: liveBlockId,
                isTextSelected: range.length > 0,
                hasFocus: hasFocus,
                richTextEditable: true,
                caretOffset: scalarOffset,
                selectedRange: range,
                selectedMarks: marks,
                selectionRectInWindow: rect,
                focusedSpecialBlockId: parent.isSpecialBlock ? liveBlockId : nil
            )
        }

        // MARK: - Canonical conversion (FR-053: supported attributes only)

        /// Builds the canonical document from the text view's attributed
        /// string, keeping only application-supported marks.
        /// `excludesDisplayStyling` drops the display-only strikethrough
        /// (todo completion) from the round trip — a completed todo's
        /// full-range strikethrough must never become a model mark.
        static func canonicalDocument(
            from attributed: NSAttributedString,
            excludesDisplayStyling: Bool = false
        ) -> RichTextDocument {
            let text = attributed.string
            let scalars = Array(text.unicodeScalars)
            var runs: [RichTextRun] = []
            var scalarCursor = 0
            attributed.enumerateAttributes(
                in: NSRange(location: 0, length: attributed.length),
                options: []
            ) { attributes, range, _ in
                let segment = (attributed.string as NSString).substring(with: range)
                let segmentScalars = segment.unicodeScalars.count
                let start = scalarCursor
                let end = min(scalars.count, scalarCursor + segmentScalars)
                scalarCursor = end
                guard end > start else { return }
                // 004 修复: the mark detection whitelist lives in
                // RichTextMarkApplier.semanticMarks(from:) — the SAME rules
                // the formatting undo snapshots use, so canonicalization
                // and undo can never drift apart.
                let marks = RichTextMarkApplier.semanticMarks(
                    from: attributes,
                    excludesDisplayStyling: excludesDisplayStyling
                )
                if let link = attributes[.link] as? URL {
                    runs.append(RichTextRun(startScalar: start, endScalar: end, marks: marks, link: link.absoluteString))
                } else if let link = attributes[.link] as? String {
                    runs.append(RichTextRun(startScalar: start, endScalar: end, marks: marks, link: link))
                } else {
                    runs.append(RichTextRun(startScalar: start, endScalar: end, marks: marks))
                }
            }
            if let last = runs.last, last.endScalar < scalars.count {
                runs.append(RichTextRun(startScalar: last.endScalar, endScalar: scalars.count, marks: []))
            }
            // Paragraphs split on newlines (scalar offsets), runs assigned by
            // containment.
            var paragraphs: [RichTextParagraph] = []
            var lineStart = 0
            var index = 0
            var lineEnds: [(start: Int, end: Int)] = []
            for scalar in scalars {
                if scalar == "\n" {
                    lineEnds.append((lineStart, index))
                    lineStart = index + 1
                }
                index += 1
            }
            lineEnds.append((lineStart, index))
            for line in lineEnds where line.end > line.start {
                let contained = runs.filter {
                    $0.startScalar >= line.start && $0.endScalar <= line.end
                }
                paragraphs.append(RichTextParagraph(
                    startScalar: line.start,
                    endScalar: line.end,
                    style: .body,
                    runs: contained
                ))
            }
            return RichTextDocument(text: text, paragraphs: paragraphs)
        }

        /// The font-affecting presentation plan for the document's runs
        /// under a typography — `(range, font, obliqueness)` entries in
        /// application order (full-range base font first, then per-run
        /// coverage segments). Covers ALL font-affecting semantic marks:
        /// bold, italic (+ CJK obliqueness) and inlineCode (monospaced).
        /// Underline / strikethrough / link are NOT font-affecting — the
        /// content push applies them separately and the in-place restyle
        /// leaves them untouched.
        private func presentationFontPlan(
            document: RichTextDocument,
            typography: EditorTypography
        ) -> [(range: NSRange, font: NSFont, obliqueness: Double?)] {
            let scalars = Array(document.text.unicodeScalars)
            let resolver = NoteFontResolver(preference: typography.fontPreference)
            let textSize = typography.textSize
            var plan: [(range: NSRange, font: NSFont, obliqueness: Double?)] = []
            let full = NSRange(location: 0, length: (document.text as NSString).length)
            plan.append((full, resolver.font(size: textSize, for: document.text), nil))
            for paragraph in document.paragraphs {
                for run in paragraph.runs {
                    let start = min(max(run.startScalar, 0), scalars.count)
                    let end = min(max(run.endScalar, start), scalars.count)
                    guard end > start else { continue }
                    var traits: NSFontDescriptor.SymbolicTraits = []
                    if run.marks.contains(.bold) { traits.insert(.bold) }
                    if run.marks.contains(.italic) { traits.insert(.italic) }
                    let runText = String(String.UnicodeScalarView(scalars[start..<end]))
                    // FR-043: apply the primary/fallback families per coverage
                    // segment so mixed Latin+CJK runs render in both families.
                    let segments = resolver.segmentedFonts(text: runText, size: textSize, traits: traits)
                    var segmentScalarOffset = start
                    for segment in segments {
                        let segmentScalars = segment.segment.unicodeScalars.count
                        let segmentStart = min(segmentScalarOffset, scalars.count)
                        let segmentEnd = min(segmentScalarOffset + segmentScalars, scalars.count)
                        guard segmentEnd > segmentStart else { continue }
                        var font = segment.font
                        if run.marks.contains(.inlineCode) {
                            font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
                        }
                        // 004 修复: italic on a family without an italic
                        // face (CJK) renders via synthesized obliqueness.
                        let obliqueness: Double? = run.marks.contains(.italic)
                            && !RichTextMarkApplier.hasTrait(.italic, in: font)
                            ? RichTextMarkApplier.synthesizedItalicObliqueness
                            : nil
                        plan.append((
                            NSRange(location: segmentStart, length: segmentEnd - segmentStart),
                            font,
                            obliqueness
                        ))
                        segmentScalarOffset = segmentEnd
                    }
                }
            }
            return plan
        }

        /// The line-height FLOOR for the system-default font path — the
        /// regular body font's TextKit default line height
        /// (`NSLayoutManager.defaultLineHeight(for:)` — NOT a magic-number
        /// table). Max-semantics: it only RAISES collapsed fallback lines
        /// back to the regular rhythm; regular text (whose natural height
        /// IS the floor) never moves, and larger fallbacks (emoji) never
        /// clamp — no maximumLineHeight by design.
        private func regularBodyLineHeightFloor(for typography: EditorTypography) -> CGFloat {
            let regular = NoteFontResolver(preference: nil).font(size: typography.textSize, for: "")
            return Self.lineHeightMetricsLayoutManager.defaultLineHeight(for: regular)
        }

        /// The paragraph style for a typography — two independent metrics
        /// compose; `nil` writes nothing at all:
        ///
        /// - `lineSpacing`: the compact/relaxed preset delta (prototype
        ///   tuning constants, see `EditorTypography.lineSpacing`; `nil`
        ///   for standard).
        /// - `minimumLineHeight`: a floor derived from the regular body
        ///   font's default line height (`regularBodyLineHeightFloor`),
        ///   applied ONLY on the system-default path
        ///   (`fontPreference == nil`). The system CJK cascade swaps
        ///   optical faces (PingFang UIText ↔ UIDisplay) when semantic
        ///   traits change, so ⌘B/⌘I collapses the baseline rhythm even
        ///   though `lineSpacing` never changes — the floor keeps the
        ///   rhythm stable. Explicit custom-font typography is untouched
        ///   by design.
        private func paragraphStyle(for typography: EditorTypography) -> NSParagraphStyle? {
            let lineSpacing = typography.lineSpacing
            let floor: CGFloat? = typography.fontPreference == nil
                ? regularBodyLineHeightFloor(for: typography)
                : nil
            guard floor != nil || lineSpacing != nil else { return nil }
            let mutable = NSMutableParagraphStyle()
            if let floor { mutable.minimumLineHeight = floor }
            if let lineSpacing { mutable.lineSpacing = lineSpacing }
            // A REAL immutable snapshot — the storage full-range attribute
            // and typingAttributes share it safely (an NSParagraphStyle is
            // immutable; a bare mutable instance could be mutated in place
            // by a future paragraph-level edit and propagate to every
            // paragraph at once).
            guard let snapshot = mutable.copy() as? NSParagraphStyle else { return mutable }
            return snapshot
        }

        /// Applies the canonical runs as NSAttributedString attributes —
        /// the CONTENT push renderer (rebuilds a fresh attributed string;
        /// setAttributedString allowed ONLY here).
        private func applyRuns(_ document: RichTextDocument, typography: EditorTypography, to textView: NSTextView) {
            let attributed = NSMutableAttributedString(string: document.text)
            for entry in presentationFontPlan(document: document, typography: typography) {
                attributed.addAttribute(.font, value: entry.font, range: entry.range)
                if let obliqueness = entry.obliqueness {
                    attributed.addAttribute(.obliqueness, value: obliqueness, range: entry.range)
                }
            }
            if let style = paragraphStyle(for: typography) {
                attributed.addAttribute(
                    .paragraphStyle,
                    value: style,
                    range: NSRange(location: 0, length: attributed.length)
                )
            }
            // Non-font-affecting marks + links (content push only — the
            // in-place restyle never rebuilds these).
            let scalars = Array(document.text.unicodeScalars)
            for paragraph in document.paragraphs {
                for run in paragraph.runs {
                    let start = min(max(run.startScalar, 0), scalars.count)
                    let end = min(max(run.endScalar, start), scalars.count)
                    guard end > start else { continue }
                    let range = NSRange(location: start, length: end - start)
                    if run.marks.contains(.underline) {
                        attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    }
                    if run.marks.contains(.strikethrough) {
                        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                    }
                    if let link = run.link, let url = URL(string: link) {
                        attributed.addAttribute(.link, value: url, range: range)
                    }
                }
            }
            let current = textView.textStorage ?? NSTextStorage()
            current.setAttributedString(attributed)
        }

        /// The PRESENTATION refresh path (Phase 3, 2026-08-14): re-renders
        /// the font-affecting attributes IN PLACE on the existing storage.
        /// Never calls setAttributedString, never assigns `textView.string`
        /// — no textDidChange, no canonicalization, no autosave, no undo
        /// registration. Preserves the selection and first responder; the
        /// typing attributes are rebuilt as typography → semantic typing
        /// marks → display styling (the display layer is an overlay, never
        /// a semantic source).
        func restyleTypographyInPlace(_ typography: EditorTypography, document: RichTextDocument, to textView: NSTextView) {
            // FR-063: defer while composing — last-write-wins.
            guard !textView.hasMarkedText(), let storage = textView.textStorage else {
                pendingTypography = typography
                return
            }
            let selection = textView.selectedRange()
            let focused = textView.window?.firstResponder === textView
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            let resolver = NoteFontResolver(preference: typography.fontPreference)
            // Set the default font BEFORE the storage pass — the property
            // setter can rewrite the whole text's font, so it must never
            // run after the per-run plan (it would wipe the segment fonts).
            textView.font = resolver.font(size: typography.textSize, for: document.text)
            storage.beginEditing()
            let full = NSRange(location: 0, length: storage.length)
            storage.removeAttribute(.obliqueness, range: full)
            // Relaxed→Default must really REMOVE the old style — remove
            // first, then conditionally add (Phase 4).
            storage.removeAttribute(.paragraphStyle, range: full)
            for entry in presentationFontPlan(document: document, typography: typography) {
                storage.addAttribute(.font, value: entry.font, range: entry.range)
                if let obliqueness = entry.obliqueness {
                    storage.addAttribute(.obliqueness, value: obliqueness, range: entry.range)
                }
            }
            if let style = paragraphStyle(for: typography) {
                storage.addAttribute(.paragraphStyle, value: style, range: full)
            }
            storage.endEditing()
            if focused {
                textView.setSelectedRange(selection)
            }
            // Typing attributes, in layer order: current typography (family
            // + size from the restyled caret font) → semantic typing marks
            // (pendingTypingMarks + the caret's content marks — derived from
            // the RESTYLED storage, so display-only styling can never leak
            // in) → display styling overlay (applyDisplayStyling below).
            var typingMarks = pendingTypingMarks
            if storage.length > 0 {
                let caretLocation = min(max(selection.location, 0), storage.length - 1)
                let caretAttributes = storage.attributes(at: caretLocation, effectiveRange: nil)
                typingMarks.formUnion(RichTextMarkApplier.semanticMarks(from: caretAttributes, excludesDisplayStyling: true))
            }
            if storage.length > 0 {
                let caretLocation = min(max(selection.location, 0), storage.length - 1)
                var typing = textView.typingAttributes
                typing[.font] = (storage.attribute(.font, at: caretLocation, effectiveRange: nil) as? NSFont)
                    ?? resolver.font(size: typography.textSize, for: "")
                typing[.obliqueness] = nil
                typing[.underlineStyle] = nil
                textView.typingAttributes = typing
            }
            RichTextMarkApplier.renderTypingAttributes(typingMarks, textView: textView, textSize: typography.textSize)
            // The spacing layer for SUBSEQUENT input (same remove-then-add
            // discipline as the storage pass).
            if let style = paragraphStyle(for: typography) {
                textView.typingAttributes[.paragraphStyle] = style
            } else {
                textView.typingAttributes[.paragraphStyle] = nil
            }
            applyDisplayStyling(to: textView)
            lastAppliedTypography = typography
            // Attribute edits do not fire didChangeText — invalidate the
            // intrinsic explicitly so the SwiftUI ScrollView re-measures
            // (font metrics changed the used rect).
            textView.invalidateIntrinsicContentSize()
        }
    }
}

// MARK: - NSTextStorageDelegate (PR2 typing normalization capture)
//
// The SDK protocol is not @MainActor-annotated (unlike NSTextViewDelegate),
// while the coordinator is. The witness is nonisolated and hops to the main
// actor via assumeIsolated — the storage calls arrive on the main thread
// (AppKit editing), the same discipline as the coordinator's deinit.

extension RichTextView.Coordinator: NSTextStorageDelegate {
    /// Apple's storage pipeline: attribute fixing → didProcessEditing →
    /// layout-manager notifications. The delegate may edit ATTRIBUTES
    /// here (never characters). We only CAPTURE — normalization runs
    /// later, after the FR-063 composition guard — so marked text is
    /// never restyled mid-composition (Invariant 5).
    public nonisolated func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        MainActor.assumeIsolated {
            guard editedMask.contains(.editedCharacters) else { return }
            // Model pushes rebuild the whole storage — their edits must not
            // feed the typing normalization.
            guard !isPushing else { return }
            if let existing = pendingCharacterEditRange {
                let unioned = NSUnionRange(existing, editedRange)
                // A zero-length range (pure deletion) must not shrink the
                // pending union — keep the wider of the two.
                pendingCharacterEditRange = unioned.length > 0 ? unioned : existing
            } else {
                pendingCharacterEditRange = editedRange
            }
        }
    }
}


// MARK: - IntrinsicSizingTextView (004 修复 2026-08-14, P0)

/// The shared width-sensitive sizing base for the note's NSTextViews
/// (`NotePaperTextView`, `CodeEditorTextView`). Both lifecycles are
/// identical (verified by the width-reflow suites): the text container
/// follows the frame width automatically, but SwiftUI only re-measures
/// once the intrinsic is invalidated — so a REAL width change must
/// invalidate it. The epsilon guard breaks the SwiftUI↔AppKit loop: a
/// pure height change (SwiftUI applying the freshly measured intrinsic)
/// must not re-invalidate.
///
/// Subclasses provide their own `intrinsicContentSize` floor/inset math.
class IntrinsicSizingTextView: NSTextView {

    /// The width the text was last laid out at.
    private var lastLayoutWidth: CGFloat = 0

    /// 004 修复 (2026-08-14, P0): invoked after a REAL width change
    /// reflows the text — `NotePaperTextView` republishes the selection
    /// rect so the contextual format row follows the fresh geometry
    /// instead of a stale pre-resize rect.
    var onWidthReflow: (() -> Void)?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - lastLayoutWidth) > 0.5
        super.setFrameSize(newSize)
        guard widthChanged else { return }
        lastLayoutWidth = newSize.width
        invalidateIntrinsicContentSize()
        onWidthReflow?()
    }

    /// 004 T063: every text edit (typing AND model pushes) re-publishes
    /// the intrinsic height so the SwiftUI ScrollView grows as the note
    /// lengthens.
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}

/// The note-paper text view: content-sized, but never shorter than a
/// comfortable typing surface. Verified 2026-08-09: a purely content-sized
/// NSTextView collapsed to a ~49pt strip for a short note, so clicks on
/// the empty paper never landed on the editor (could not focus / type);
/// the old "fixed 300pt slot" instead bottom-anchored the text because
/// SwiftUI frame alignment does not apply to representable frames. The
/// intrinsic-size override keeps the text top-anchored (with the native
/// inset) while giving the paper a full-height click target, and grows
/// naturally for long notes (the enclosing SwiftUI ScrollView scrolls).
final class NotePaperTextView: IntrinsicSizingTextView {
    /// The default minimum paper height: an empty note is a comfortable
    /// clickable typing surface that still leaves headroom for the
    /// ScrollView. The PRIMARY paper keeps this value; trailing/todo
    /// editors set `minimumHeight = 0` (content-sized — 004 修复).
    static let minimumPaperHeight: CGFloat = 320

    /// 004 修复: per-instance minimum height (primary = 320; trailing/todo
    /// editors = 0 so an inserted block no longer renders a second paper).
    var minimumHeight: CGFloat = NotePaperTextView.minimumPaperHeight

    /// 004 修复 (2026-08-13 用户实测第二轮): bottom-inset collapse. When
    /// blocks follow the paper, the BOTTOM text-container inset becomes
    /// dead paper under the last ink line (read by the user as 大段间隔
    /// before the inserted block) — the stack spacing already owns the
    /// rhythm below. The top inset always survives (first-line breathing
    /// room under the controls row). NSTextView insets are symmetric, so
    /// the collapse happens in the intrinsic height: the text keeps its
    /// top-inset origin, the frame simply stops at the last line.
    var collapsesBottomInset: Bool = false

    /// NSView's native baseline metric — NSTextView does NOT override it
    /// (the platform value is unusable), so populate it with the layout
    /// manager's REAL first-line baseline (004 修复 2026-08-14, P0: the
    /// todo row aligns its checkbox to the first line via this override).
    override var firstBaselineOffsetFromTop: CGFloat {
        if let layoutManager, let container = textContainer {
            layoutManager.ensureLayout(for: container)
            if let storage = textStorage, storage.length > 0 {
                // lineFragmentRect is in container content coordinates —
                // it does NOT include the text-container inset.
                let rect = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
                let firstFont = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    ?? font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
                return rect.minY + firstFont.ascender + textContainerInset.height
            }
        }
        let current = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        return textContainerInset.height + current.ascender
    }

    /// The FIRST LINE's typographic center, measured from the text view's
    /// top (004 修复 2026-08-14, P1; PR1 rework 2026-08-14): the REAL TextKit
    /// first-line baseline minus the NOMINAL body font's optical offset
    /// `(ascender + descender) / 2` — independent of line spacing, wrapping
    /// width, line count and first-character formatting. `alignmentFont`
    /// MUST be the same nominal body font the todo row seeds its checkbox
    /// with (`NoteFontResolver.nominalBodyFont`) — the invariant is
    /// "checkbox center == actual baseline - (nominalAsc + nominalDesc)/2",
    /// NOT a fixed position: bold / inline code / CJK / emoji move the
    /// checkbox only when TextKit's own line metrics move the baseline.
    ///
    /// Baseline acquisition (calibrated by TodoFirstLineMetricTests):
    /// C3a — `fragment.minY + location(forGlyphAt: 0).y` (the glyph location
    /// is relative to the line-fragment origin). The semantic reference is
    /// C3b — `fragment.maxY - typesetter.baselineOffset(in:glyphIndex:)` —
    /// and the calibration suite pins C3a to it; if a future macOS release
    /// diverges, switch this branch to C3b.
    func firstLineTypographicCenterFromTop(alignmentFont: NSFont) -> CGFloat {
        if let layoutManager, let container = textContainer,
           let storage = textStorage, storage.length > 0,
           container.size.width > 1.0 {
            layoutManager.ensureLayout(for: container)
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: 0).y + textContainerInset.height
            return baseline - (alignmentFont.ascender + alignmentFont.descender) / 2
        }
        // Empty text / zero-width container: no authoritative geometry —
        // the seed-formula family (the nominal font's own typographic
        // center), identical to the TodoBlockView seed.
        return textContainerInset.height + (alignmentFont.ascender - alignmentFont.descender) / 2
    }

    override var intrinsicContentSize: NSSize {
        let topInset = textContainerInset.height
        let lineFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = lineFont.ascender - lineFont.descender + lineFont.leading
        let oneLineFloor = topInset + ceil(lineHeight)
        let floor = minimumHeight > 0 ? minimumHeight : oneLineFloor
        // 2026-08-14 fix (insertion gap): a freshly inserted editor's
        // container is still 0 wide on the FIRST measurement — a width-0
        // layout puts EVERY glyph on its own line, so usedRect reports a
        // bogus TALL height and the first frame inflates the gap until a
        // width change re-measures. Zero-width containers report the floor
        // (no authoritative geometry); the first real frame triggers the
        // width-change re-measure.
        if let container = textContainer, container.size.width <= 1.0 {
            return NSSize(width: NSView.noIntrinsicMetric, height: floor)
        }
        // 004 T063 (2026-08-13): force the layout pass before reading
        // usedRect — the enclosing SwiftUI ScrollView relies on this
        // intrinsic height to grow its content and scroll a long note
        // (without this, usedRect stays partial and the paper clips).
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        let used = layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? 0
        let bottomInset = collapsesBottomInset ? 0 : textContainerInset.height
        let contentHeight = used + topInset + bottomInset
        // The floor: the primary paper keeps its 320pt click target; a
        // content-sized editor (minimumHeight == 0 — trailing/todo/primary-
        // with-blocks) keeps ONE line so an empty block never collapses to
        // 0pt (the caret/click target must survive the zero vertical inset).
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(contentHeight, floor)
        )
    }
}
