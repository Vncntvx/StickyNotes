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
    let textSize: CGFloat
    /// The FR-043 global font preference applied to note text (system font
    /// when no preference is stored).
    let fontResolver: NoteFontResolver
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
    /// 004 修复: insertion-focus request — this editor becomes first
    /// responder (caret at start) once it lands in a window.
    let requestFocus: Bool
    let onFocusRequestHandled: () -> Void

    public init(
        document: RichTextDocument,
        textSize: CGFloat,
        fontResolver: NoteFontResolver = .load(),
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
        requestFocus: Bool = false,
        onFocusRequestHandled: @escaping () -> Void = {}
    ) {
        self.document = document
        self.textSize = textSize
        self.fontResolver = fontResolver
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
        self.requestFocus = requestFocus
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
        textView.font = fontResolver.font(size: textSize, for: "")
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        // 004 修复: 尾部/todo 编辑器内容自适应（无 320 最小高度）；主纸面
        // 保持 NotePaperTextView 默认值。
        if let minimumHeight {
            textView.minimumHeight = minimumHeight
        }
        textView.collapsesBottomInset = collapsesBottomInset
        context.coordinator.apply(document: document, textSize: textSize, resolver: fontResolver, to: textView)
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
        // Push model changes only when the document actually differs (the
        // user is editing — never clobber the live text).
        if textView.string != document.text {
            context.coordinator.apply(document: document, textSize: textSize, resolver: fontResolver, to: textView)
        } else if textView.font?.pointSize != textSize {
            textView.font = fontResolver.font(size: textSize, for: textView.string)
        }
        // 004 修复: 显示专用样式（todo 完成态）每次更新对齐——文本未变也
        // 要跟随勾选状态切换。
        context.coordinator.applyDisplayStyling(to: textView)
        if requestFocus {
            context.coordinator.requestFocusIfNeeded(textView)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextView
        /// Suppresses delegate-driven commits while the model is pushing a
        /// document in (avoid echo loops).
        private var isPushing = false
        /// 004 T037: the live text view + bridge (weak text view — the
        /// bridge must never outlive the editor).
        private weak var liveTextView: NSTextView?
        private weak var liveBridge: EditorSelectionBridge?
        private var liveBlockId: UUID?
        /// 004 修复: insertion-focus requests are handled once per editor.
        private var didHandleFocusRequest = false

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

        /// 004 修复: routes this editor's undo to the window-level shared
        /// UndoManager — typing in ANY block lands on the same stack as
        /// structural changes (⌘Z/⌘⇧Z span the whole note).
        public func undoManager(for view: NSTextView) -> UndoManager? {
            parent.undoManager
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

        private func republishSelection() {
            guard let textView = liveTextView else { return }
            publishSelection(from: textView)
        }

        func apply(document: RichTextDocument, textSize: CGFloat, resolver: NoteFontResolver, to textView: NSTextView) {
            isPushing = true
            defer { isPushing = false }
            // 004 修复: model pushes must not register undo actions AND must
            // not wipe the shared undo stack (clearing is the structural
            // change's job — NoteWindowHostModel).
            let undo = textView.undoManager
            undo?.disableUndoRegistration()
            defer { undo?.enableUndoRegistration() }
            textView.font = resolver.font(size: textSize, for: document.text)
            textView.string = document.text
            applyRuns(document, textSize: textSize, resolver: resolver, to: textView)
            applyDisplayStyling(to: textView)
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
        /// responder with the caret at the start, then reports handled.
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
                textView.setSelectedRange(NSRange(location: 0, length: 0))
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
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                    handler()
                } else {
                    self?.requestFocusIfNeeded(textView)
                }
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: never persist partial IME composition.
            guard !textView.hasMarkedText() else { return }
            let document = Self.canonicalDocument(
                from: textView.attributedString(),
                excludesDisplayStyling: parent.displayStyling?.strikethrough == true
            )
            parent.onCommit(document)
            // 004 修复 (2026-08-13 用户实测): FR-063 suppresses selection
            // publishes DURING composition — republish after the commit so
            // the insertion-target registry never lags behind the caret
            // (stale offsets made window-level Insert split at the wrong
            // position right after CJK input).
            publishSelection(from: textView)
        }

        public func textDidEndEditing(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            parent.onFocusChange(false, textView.hasMarkedText())
            publishSelection(from: textView)
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true, false)
            if let textView = notification.object as? NSTextView {
                publishSelection(from: textView)
            }
        }

        // MARK: - 004 T037 (FR-012): selection observation

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: do not publish selection during IME composition.
            guard !textView.hasMarkedText() else { return }
            publishSelection(from: textView)
        }

        /// Publishes the current selection/focus snapshot into the bridge.
        func publishSelection(from textView: NSTextView) {
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
            bridge.publish(
                from: textView,
                caretBlockId: liveBlockId,
                isTextSelected: range.length > 0,
                hasFocus: hasFocus,
                richTextEditable: true,
                caretOffset: scalarOffset,
                selectedRange: range,
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
                var marks: Set<RichTextMark> = []
                if let font = attributes[.font] as? NSFont {
                    let traits = font.fontDescriptor.symbolicTraits
                    if traits.contains(.bold) { marks.insert(.bold) }
                    // 004 修复: synthesized oblique (matrix) fonts count as
                    // italic, and CJK italic is synthesized via `.obliqueness`
                    // (no italic face) — both must survive the round trip.
                    if RichTextMarkApplier.hasTrait(.italic, in: font) || attributes[.obliqueness] != nil {
                        marks.insert(.italic)
                    }
                    let family = font.familyName ?? ""
                    if family.localizedCaseInsensitiveContains("mono") || family.localizedCaseInsensitiveContains("courier") {
                        marks.insert(.inlineCode)
                    }
                }
                if attributes[.underlineStyle] != nil { marks.insert(.underline) }
                if !excludesDisplayStyling, attributes[.strikethroughStyle] != nil { marks.insert(.strikethrough) }
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

        /// Applies the canonical runs as NSAttributedString attributes.
        private func applyRuns(_ document: RichTextDocument, textSize: CGFloat, resolver: NoteFontResolver, to textView: NSTextView) {
            let attributed = NSMutableAttributedString(string: document.text)
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.font, value: resolver.font(size: textSize, for: document.text), range: full)
            let scalars = Array(document.text.unicodeScalars)
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
                        attributed.addAttribute(
                            .font,
                            value: font,
                            range: NSRange(location: segmentStart, length: segmentEnd - segmentStart)
                        )
                        // 004 修复: italic on a family without an italic
                        // face (CJK) renders via synthesized obliqueness.
                        if run.marks.contains(.italic), !RichTextMarkApplier.hasTrait(.italic, in: font) {
                            attributed.addAttribute(
                                .obliqueness,
                                value: RichTextMarkApplier.synthesizedItalicObliqueness,
                                range: NSRange(location: segmentStart, length: segmentEnd - segmentStart)
                            )
                        }
                        segmentScalarOffset = segmentEnd
                    }
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
final class NotePaperTextView: NSTextView {
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

    override var intrinsicContentSize: NSSize {
        // 004 T063 (2026-08-13): force the layout pass before reading
        // usedRect — the enclosing SwiftUI ScrollView relies on this
        // intrinsic height to grow its content and scroll a long note
        // (without this, usedRect stays partial and the paper clips).
        if let layoutManager, let textContainer {
            layoutManager.ensureLayout(for: textContainer)
        }
        let used = layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? 0
        let topInset = textContainerInset.height
        let bottomInset = collapsesBottomInset ? 0 : textContainerInset.height
        let contentHeight = used + topInset + bottomInset
        // The floor: the primary paper keeps its 320pt click target; a
        // content-sized editor (minimumHeight == 0 — trailing/todo/primary-
        // with-blocks) keeps ONE line so an empty block never collapses to
        // 0pt (the caret/click target must survive the zero vertical inset).
        let lineFont = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = lineFont.ascender - lineFont.descender + lineFont.leading
        let oneLineFloor = topInset + ceil(lineHeight)
        let floor = minimumHeight > 0 ? minimumHeight : oneLineFloor
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(contentHeight, floor)
        )
    }

    /// 004 T063: every text edit (typing AND model pushes) re-publishes
    /// the intrinsic height so the SwiftUI ScrollView grows as the note
    /// lengthens.
    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}
