import Foundation
import Domain

// MARK: - MarkdownTransformer (T073)
//
// Per tasks.md T073 and plan §Markdown transformation:
//
// - Implemented as an editor transformation state machine, not a Markdown
//   document mode. Line-level (heading/bullet/todo/code-fence) and inline
//   (bold/italic/strike/inline-code) categories per spec.
// - Ignores unmatched delimiters.
// - Does NOT transform while an IME has active marked text.
// - Preserves Chinese/mixed composition.
// - Treats conversion + delimiter removal as ONE undo group (one Undo
//   restores exact source delimiters).
// - No conversion inside code blocks except closing fences.
// - Defines cursor placement after conversion.
// - Unit-testable without SwiftUI.
//
// Constitution V (structured editor integrity): Markdown is an *input
// convenience* with single-Undo. It is not a storage format — the canonical
// rich-text model is the source of truth.

// MARK: - Transform decisions

/// The kind of transform the state machine decided to apply. The editor
/// command layer (T074) uses this to drive the UndoManager grouping and
/// cursor placement.
public enum MarkdownTransform: Sendable, Equatable {
    /// No transform — the typed input is ordinary text.
    case none

    /// A line-level transform (heading / bullet / todo / code-fence) that
    /// replaces the line's prefix and sets the paragraph style.
    case lineLevel(MarkdownLineTransform)

    /// An inline transform (bold / italic / strike / inline-code) that
    /// removes the delimiters and applies the mark to the enclosed text.
    case inline(MarkdownInlineTransform, MarkdownInlineRange)
}

/// Line-level transforms per spec FR-067..FR-070.
public enum MarkdownLineTransform: String, Sendable, Equatable {
    case heading1   // "# "
    case heading2   // "## "
    case heading3   // "### "
    case bullet     // "- " or "* "
    case todo       // "- [ ] " / "- [x] "
    case codeFence  // ``` opening or closing fence
}

/// Inline transforms per spec FR-073..FR-076.
public enum MarkdownInlineTransform: String, Sendable, Equatable {
    case bold        // **text** or __text__
    case italic      // *text* or _text_
    case strikethrough  // ~~text~~
    case inlineCode  // `text`
}

/// The scalar-offset range of the enclosed text (after delimiter removal).
public struct MarkdownInlineRange: Sendable, Equatable {
    public var startScalar: Int
    public var endScalar: Int
    public init(startScalar: Int, endScalar: Int) {
        self.startScalar = startScalar
        self.endScalar = endScalar
    }
}

// MARK: - MarkdownTransformer

/// The state machine. Pure functions, no SwiftUI/AppKit dependencies —
/// fully testable from EditorCoreTests.
public enum MarkdownTransformer {

    // MARK: - Line-level transforms

    /// Decides whether the line should be transformed. Returns `.none` if
    /// the prefix doesn't match a known Markdown line opener, if IME
    /// composition is active, or if the line is inside a code block (the
    /// caller passes `insideCodeBlock`; only the closing fence ``` is
    /// recognized inside a code block).
    public static func decideLineLevel(
        line: String,
        insideCodeBlock: Bool,
        hasIMEComposition: Bool
    ) -> MarkdownTransform {
        guard !hasIMEComposition else { return .none }

        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Inside a code block, only the closing fence is recognized.
        if insideCodeBlock {
            if trimmed == "```" || trimmed.hasPrefix("```") {
                return .lineLevel(.codeFence)
            }
            return .none
        }

        // Opening code fence (with optional language label).
        if trimmed.hasPrefix("```") { return .lineLevel(.codeFence) }

        // Headings: "# ", "## ", "### " (trailing space required).
        if line.hasPrefix("# ") { return .lineLevel(.heading1) }
        if line.hasPrefix("## ") { return .lineLevel(.heading2) }
        if line.hasPrefix("### ") { return .lineLevel(.heading3) }

        // Bullets and todos: "- " / "* ".
        if line.hasPrefix("- ") || line.hasPrefix("* ") {
            // Todo shortcut: "- [ ] " / "- [x] " / "* [ ] " / "* [x] ".
            if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") ||
                line.hasPrefix("* [ ] ") || line.hasPrefix("* [x] ") {
                return .lineLevel(.todo)
            }
            return .lineLevel(.bullet)
        }
        return .none
    }

    /// Applies a line-level transform: removes the Markdown prefix and
    /// returns the transformed line text + the cursor offset within the
    /// line (scalar offsets). For `.codeFence`, the line becomes empty
    /// (the editor enters/exits code-block mode).
    public static func applyLineLevel(
        _ transform: MarkdownLineTransform,
        toLine line: String
    ) -> (newLine: String, cursorOffset: Int) {
        switch transform {
        case .heading1:
            let rest = String(line.dropFirst(2))
            return (rest, rest.unicodeScalars.count)
        case .heading2:
            let rest = String(line.dropFirst(3))
            return (rest, rest.unicodeScalars.count)
        case .heading3:
            let rest = String(line.dropFirst(4))
            return (rest, rest.unicodeScalars.count)
        case .bullet:
            let rest = String(line.dropFirst(2))
            return (rest, rest.unicodeScalars.count)
        case .todo:
            // "- [ ] task" → "task". The todo block identity is created by
            // the editor; the text is the task description.
            let rest = String(line.dropFirst(6))
            return (rest, rest.unicodeScalars.count)
        case .codeFence:
            // The fence is consumed; the line becomes empty. The editor
            // toggles code-block mode.
            return ("", 0)
        }
    }

    // MARK: - Inline transforms
    //
    // Triggered after the user types a closing delimiter. The transformer
    // checks that opening + closing delimiters are balanced and that the
    // enclosed text is non-empty. Unmatched delimiters are left as-is.

    /// Decides whether an inline transform should fire at the given cursor
    /// offset. `text` is the full line up to and including the just-typed
    /// closing delimiter.
    public static func decideInline(
        text: String,
        cursorScalarOffset: Int,
        insideCodeBlock: Bool,
        hasIMEComposition: Bool
    ) -> MarkdownTransform {
        guard !insideCodeBlock, !hasIMEComposition else { return .none }

        let scalars = Array(text.unicodeScalars)
        guard cursorScalarOffset > 0, cursorScalarOffset <= scalars.count else { return .none }

        // Try patterns in order of decreasing delimiter length so that
        // `**bold**` is matched as bold (not italic) and `~~strike~~` is
        // matched as strike.
        // Order: inline-code (`), strikethrough (~~), bold (** or __), italic (* or _)
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "`", mark: .inlineCode) {
            return .inline(.inlineCode, r)
        }
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "~~", mark: .strikethrough) {
            return .inline(.strikethrough, r)
        }
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "**", mark: .bold) {
            return .inline(.bold, r)
        }
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "__", mark: .bold) {
            return .inline(.bold, r)
        }
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "*", mark: .italic) {
            return .inline(.italic, r)
        }
        if let r = matchBalanced(scalars: scalars, cursor: cursorScalarOffset, delim: "_", mark: .italic) {
            return .inline(.italic, r)
        }
        return .none
    }

    /// Searches backwards from `cursor` for a matching opening delimiter
    /// and returns the scalar range of the enclosed text (after delimiter
    /// removal). Returns `nil` if no balanced match (unmatched delimiter →
    /// no transform).
    private static func matchBalanced(
        scalars: [Unicode.Scalar],
        cursor: Int,
        delim: String,
        mark: MarkdownInlineTransform
    ) -> MarkdownInlineRange? {
        _ = mark
        let delimScalars = Array(delim.unicodeScalars)
        let delimLen = delimScalars.count
        // The closing delimiter occupies [cursor - delimLen, cursor).
        let closingStart = cursor - delimLen
        guard closingStart >= 0 else { return nil }

        // Verify the closing delimiter is actually present.
        for j in 0..<delimLen {
            if scalars[closingStart + j] != delimScalars[j] { return nil }
        }

        // Search backwards for the opening delimiter, leaving non-empty
        // text between opening-end and closing-start.
        var i = closingStart - delimLen  // candidate opening start
        while i >= 0 {
            var match = true
            for j in 0..<delimLen {
                if scalars[i + j] != delimScalars[j] { match = false; break }
            }
            if match {
                let innerStart = i + delimLen
                let innerEnd = closingStart
                if innerEnd > innerStart {
                    // Return the range of the enclosed text in ORIGINAL text
                    // coordinates. applyInline removes the opening delimiter
                    // [i, innerStart) and closing delimiter [innerEnd, innerEnd+delimLen).
                    return MarkdownInlineRange(startScalar: innerStart, endScalar: innerEnd)
                }
                // Empty enclosed text (e.g. `**""**`) — not a transform.
                return nil
            }
            i -= 1
        }
        return nil
    }

    /// Applies an inline transform: removes the delimiters and returns the
    /// new text + cursor offset. The mark itself is applied to the
    /// `MarkdownInlineRange` by the editor's RichTextAdapter (which maps
    /// scalar offsets to RichTextRun marks).
    public static func applyInline(
        _ transform: MarkdownInlineTransform,
        range: MarkdownInlineRange,
        to text: String
    ) -> (newText: String, cursorOffset: Int) {
        let scalars = Array(text.unicodeScalars)
        let delimLen = delimiterLength(for: transform)
        // Remove the closing delimiter [range.end, range.end + delimLen) and
        // the opening delimiter [range.start - delimLen, range.start).
        // After removal the enclosed text occupies [range.start, range.end).
        guard range.startScalar >= delimLen,
              range.endScalar + delimLen <= scalars.count else {
            return (text, text.unicodeScalars.count)
        }
        var result: [Unicode.Scalar] = []
        result.append(contentsOf: scalars[0..<(range.startScalar - delimLen)])
        result.append(contentsOf: scalars[range.startScalar..<range.endScalar])
        result.append(contentsOf: scalars[(range.endScalar + delimLen)...])
        let newText = String(String.UnicodeScalarView(result))
        // Cursor lands at the end of the enclosed text in the NEW text:
        // (start of enclosed text in new text) + (enclosed length)
        // = (range.startScalar - delimLen) + (range.endScalar - range.startScalar)
        // = range.endScalar - delimLen
        return (newText, range.endScalar - delimLen)
    }

    /// Returns the delimiter length for a transform.
    private static func delimiterLength(for transform: MarkdownInlineTransform) -> Int {
        switch transform {
        case .bold: return 2          // ** or __
        case .italic: return 1        // * or _
        case .strikethrough: return 2 // ~~
        case .inlineCode: return 1    // `
        }
    }

    // MARK: - Undo restoration
    //
    // The single-Undo contract (FR-077): one Undo restores the exact source
    // delimiters. The editor achieves this by grouping the conversion +
    // delimiter-removal as one undo group via EditorCommands (T074). The
    // transformer itself is stateless; the editor caches the pre-transform
    // text and restores it on undo.

    /// Returns the original source text for a transform, so the editor can
    /// restore it on single-Undo. The editor passes the `originalText` it
    /// cached before applying the transform; we return it verbatim. This
    /// keeps the transformer stateless — the editor owns the undo stack.
    public static func undoSourceText(
        for transform: MarkdownTransform,
        currentText: String,
        originalText: String
    ) -> String {
        _ = transform; _ = currentText
        return originalText
    }
}
