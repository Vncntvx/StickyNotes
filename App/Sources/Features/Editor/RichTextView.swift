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
    /// The canonical document currently owned by the model.
    let document: RichTextDocument
    let textSize: CGFloat
    /// Reports a canonical document produced by editing (only supported
    /// attributes survive — FR-053).
    let onCommit: (RichTextDocument) -> Void
    /// Reports focus changes with the IME marked-text state (FR-050a
    /// removal must not fire during composition — FR-063).
    let onFocusChange: (Bool, Bool) -> Void

    public init(
        document: RichTextDocument,
        textSize: CGFloat,
        onCommit: @escaping (RichTextDocument) -> Void,
        onFocusChange: @escaping (Bool, Bool) -> Void = { _, _ in }
    ) {
        self.document = document
        self.textSize = textSize
        self.onCommit = onCommit
        self.onFocusChange = onFocusChange
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
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
        textView.textContainerInset = NSSize(width: 2, height: 6)
        textView.font = .systemFont(ofSize: textSize)
        textView.delegate = context.coordinator
        textView.autoresizingMask = [.width]
        context.coordinator.apply(document: document, textSize: textSize, to: textView)
        return textView
    }

    public func updateNSView(_ textView: NSTextView, context: Context) {
        // Push model changes only when the document actually differs (the
        // user is editing — never clobber the live text).
        if textView.string != document.text {
            context.coordinator.apply(document: document, textSize: textSize, to: textView)
        } else if textView.font?.pointSize != textSize {
            textView.font = .systemFont(ofSize: textSize)
        }
    }

    // MARK: - Coordinator

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        private var parent: RichTextView
        /// Suppresses delegate-driven commits while the model is pushing a
        /// document in (avoid echo loops).
        private var isPushing = false

        init(_ parent: RichTextView) {
            self.parent = parent
        }

        func apply(document: RichTextDocument, textSize: CGFloat, to textView: NSTextView) {
            isPushing = true
            defer { isPushing = false }
            textView.font = .systemFont(ofSize: textSize)
            textView.string = document.text
            applyRuns(document, textSize: textSize, to: textView)
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
        }

        public func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true, false)
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
        private func applyRuns(_ document: RichTextDocument, textSize: CGFloat, to textView: NSTextView) {
            let attributed = NSMutableAttributedString(string: document.text)
            let full = NSRange(location: 0, length: attributed.length)
            attributed.addAttribute(.font, value: NSFont.systemFont(ofSize: textSize), range: full)
            let scalars = Array(document.text.unicodeScalars)
            for paragraph in document.paragraphs {
                for run in paragraph.runs {
                    let start = min(max(run.startScalar, 0), scalars.count)
                    let end = min(max(run.endScalar, start), scalars.count)
                    guard end > start else { continue }
                    let range = NSRange(location: start, length: end - start)
                    var font = NSFont.systemFont(ofSize: textSize)
                    var traits: NSFontDescriptor.SymbolicTraits = []
                    if run.marks.contains(.bold) { traits.insert(.bold) }
                    if run.marks.contains(.italic) { traits.insert(.italic) }
                    if !traits.isEmpty {
                        let descriptor = font.fontDescriptor.withSymbolicTraits(traits)
                        font = NSFont(descriptor: descriptor, size: textSize) ?? font
                    }
                    if run.marks.contains(.inlineCode) {
                        font = NSFont.monospacedSystemFont(ofSize: textSize, weight: .regular)
                    }
                    attributed.addAttribute(.font, value: font, range: range)
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
