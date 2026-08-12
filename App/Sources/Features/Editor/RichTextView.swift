import SwiftUI
import AppKit
import Domain
import EditorCore

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
    static let textContainerHorizontalInset: CGFloat = 0
    static let lineFragmentPadding: CGFloat = 0
    static let textContainerVerticalInset: CGFloat = 12

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

    public init(
        document: RichTextDocument,
        textSize: CGFloat,
        fontResolver: NoteFontResolver = .load(),
        onCommit: @escaping (RichTextDocument) -> Void,
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in },
        selectionBridge: EditorSelectionBridge? = nil,
        richTextBlockId: UUID? = nil
    ) {
        self.document = document
        self.textSize = textSize
        self.fontResolver = fontResolver
        self.onCommit = onCommit
        self.onFocusChange = onFocusChange
        self.selectionBridge = selectionBridge
        self.richTextBlockId = richTextBlockId
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
        textView.textContainerInset = NSSize(
            width: Self.textContainerHorizontalInset,
            height: Self.textContainerVerticalInset
        )
        textView.textContainer?.lineFragmentPadding = Self.lineFragmentPadding
        textView.font = fontResolver.font(size: textSize, for: "")
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        context.coordinator.apply(document: document, textSize: textSize, resolver: fontResolver, to: textView)
        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // 004 T037: keep the bridge attached to the live text view.
        context.coordinator.attach(textView, bridge: selectionBridge, blockId: richTextBlockId)
        // Push model changes only when the document actually differs (the
        // user is editing — never clobber the live text).
        if textView.string != document.text {
            context.coordinator.apply(document: document, textSize: textSize, resolver: fontResolver, to: textView)
        } else if textView.font?.pointSize != textSize {
            textView.font = fontResolver.font(size: textSize, for: textView.string)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: RichTextView
        /// Suppresses delegate-driven commits while the model is pushing a
        /// document in (avoid echo loops).
        private var isPushing = false
        /// 004 T037: the live text view + bridge (weak text view — the
        /// bridge must never outlive the editor).
        private weak var liveTextView: NSTextView?
        private weak var liveBridge: EditorSelectionBridge?
        private var liveBlockId: UUID?

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
            textView.font = resolver.font(size: textSize, for: document.text)
            textView.string = document.text
            applyRuns(document, textSize: textSize, resolver: resolver, to: textView)
            textView.undoManager?.removeAllActions()
        }

        public func textDidChange(_ notification: Notification) {
            guard !isPushing, let textView = notification.object as? NSTextView else { return }
            // FR-063: never persist partial IME composition.
            guard !textView.hasMarkedText() else { return }
            let document = Self.canonicalDocument(from: textView.attributedString())
            parent.onCommit(document)
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
            bridge.publish(
                caretBlockId: liveBlockId,
                isTextSelected: range.length > 0,
                hasFocus: hasFocus,
                caretOffset: range.length > 0 ? range.location : range.location,
                selectedRange: range,
                selectionRectInWindow: rect,
                focusedSpecialBlockId: nil
            )
        }

        // MARK: - Canonical conversion (FR-053: supported attributes only)

        /// Builds the canonical document from the text view's attributed
        /// string, keeping only application-supported marks.
        static func canonicalDocument(from attributed: NSAttributedString) -> RichTextDocument {
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
                    if traits.contains(.italic) { marks.insert(.italic) }
                    let family = font.familyName ?? ""
                    if family.localizedCaseInsensitiveContains("mono") || family.localizedCaseInsensitiveContains("courier") {
                        marks.insert(.inlineCode)
                    }
                }
                if attributes[.underlineStyle] != nil { marks.insert(.underline) }
                if attributes[.strikethroughStyle] != nil { marks.insert(.strikethrough) }
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
    /// The minimum paper height: an empty note is a comfortable clickable
    /// typing surface that still leaves headroom for the ScrollView.
    static let minimumPaperHeight: CGFloat = 320

    override var intrinsicContentSize: NSSize {
        let used = layoutManager?.usedRect(for: textContainer ?? NSTextContainer()).height ?? 0
        let contentHeight = used + textContainerInset.height * 2
        return NSSize(
            width: NSView.noIntrinsicMetric,
            height: max(contentHeight, Self.minimumPaperHeight)
        )
    }
}
