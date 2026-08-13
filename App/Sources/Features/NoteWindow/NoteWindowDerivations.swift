import AppKit
import Domain

// MARK: - NoteToolbarSpec (004 FR-015c/Q3, contracts §2)

/// The fixed toolbar-item identifier set (product-fixed: no user
/// customization palette; the system overflow chevron handles narrow
/// widths). Identifiers are plain strings here so the constants are
/// Sendable and testable; `NoteToolbarController` wraps them in
/// `NSToolbarItem.Identifier` at runtime.
public enum NoteToolbarSpec {

    public static let pinIdentifier = "note.toolbar.pin"
    public static let appearanceIdentifier = "note.toolbar.appearance"
    public static let insertIdentifier = "note.toolbar.insert"
    public static let moreIdentifier = "note.toolbar.more"

    /// The full fixed set, in layout order.
    public static let itemIdentifierStrings: [String] = [
        pinIdentifier,
        appearanceIdentifier,
        insertIdentifier,
        moreIdentifier,
    ]

    public static let toolbarIdentifier = "note.window.toolbar"

    // MARK: Visual density (004 T064, 2026-08-13 user feedback)
    //
    // The glass toolbar read as a LARGE segmented control (four heavy
    // capsules inside a heavy outer capsule). System-native density
    // reduction: `.small` size mode + `.small` control size land in
    // AppKit's medium density band (rounded-rect rather than capsule-heavy)
    // — toolbar height drops ~10–15%, per-item horizontal padding ~15–20%,
    // while hover/press morphing stays system provided (FR-022/FR-034: no
    // hand-drawn chrome). Single-constant tuning points if the density
    // needs another step.
    public static let toolbarSizeMode: NSToolbar.SizeMode = .small
    public static let buttonControlSize: NSControl.ControlSize = .small

    // MARK: Visual styling (004 T067, 2026-08-13 user feedback)
    //
    // ONE glass container + four borderless toolbar buttons: at rest the
    // items have NO capsule boundaries (hover/press/keyboard focus shows
    // the system response) — Liquid Glass stays as the overall surface,
    // not as per-item pills. Symbols are tight (hit areas ~36–42 pt);
    // the palette is optically 1pt smaller; More uses the light
    // `ellipsis` glyph (not ellipsis.circle — one less circular layer).
    public static let buttonBezelStyle: NSButton.BezelStyle = .toolbar
    public static let symbolPointSize: CGFloat = 14
    public static let paletteSymbolPointSize: CGFloat = 13
    public static let pinSymbolName = "pin"
    public static let appearanceSymbolName = "paintpalette"
    public static let insertSymbolName = "plus"
    public static let moreSymbolName = "ellipsis"

    // MARK: Appearance panel placement (004 T071, 2026-08-13)
    //
    // The panel is a borderless child window placed from the note window's
    // screen frame (NSPopover anchoring is unreliable on the macOS 27
    // Liquid Glass shell). Leading offset ≈ traffic lights (~78) + pin
    // item (~36) → the palette button's leading edge; top offset covers
    // the titlebar + toolbar band (small size mode).
    public static let panelLeadingInset: CGFloat = 110
    public static let panelTopInset: CGFloat = 56
}

// MARK: - NoteWindowDerivations (004, data-model.md §4 pure functions)
//
// Pure, IO-free helpers for the 004 redesign — every function here is
// directly unit-testable (data-model.md §4, tasks T006/T007/T009/T010):
// window-title derivation, insertion-target resolution, rich-text block
// split, opacity percent formatting, toolbar visibility priority, and the
// palette-storage mapping shared by the appearance panel and menus.

// MARK: - Insertion target (004 FR-010/Q4, data-model.md §4.2)

/// Where a window-level insertion lands.
public enum InsertionTarget: Equatable, Sendable {
    /// Split the rich-text block at the caret offset and insert there
    /// (runs preserved — FR-010).
    case caretSplit(blockId: UUID, offset: Int)
    /// Insert directly after a focused special block.
    case afterBlock(blockId: UUID)
    /// Append at the end (default `max+1024` behavior).
    case append
}

/// The editor's insertion context, snapshotted when an async insertion is
/// initiated (contracts §5: async flows capture the target up front and
/// degrade to `.append` when it goes stale).
public struct InsertionContext: Equatable, Sendable {
    /// The rich-text block containing the caret, and its scalar offset.
    public var caretBlockId: UUID?
    public var caretOffset: Int?
    /// A focused special block (todo/code/file/image/screenshot).
    public var focusedSpecialBlockId: UUID?

    public init(
        caretBlockId: UUID? = nil,
        caretOffset: Int? = nil,
        focusedSpecialBlockId: UUID? = nil
    ) {
        self.caretBlockId = caretBlockId
        self.caretOffset = caretOffset
        self.focusedSpecialBlockId = focusedSpecialBlockId
    }
}

// MARK: - Document focus request (004 修复 2026-08-14, P0)

/// A document-level focus request: which block's editor becomes first
/// responder, and where the caret lands. The former `pendingFocusBlockId`
/// carried no position — tail continuation needs `.end` to resume typing
/// at the end of an existing trailing paragraph.
public struct EditorFocusRequest: Equatable, Sendable {
    public enum Position: Equatable, Sendable {
        /// Caret at the block's start (insertion focus).
        case start
        /// Caret at the block's end (tail continuation).
        case end
    }

    public var blockId: UUID
    public var position: Position

    public init(blockId: UUID, position: Position = .start) {
        self.blockId = blockId
        self.position = position
    }
}

// MARK: - Pure functions

public enum NoteWindowDerivations {

    // MARK: Title derivation (004 FR-003, data-model.md §4.1)

    /// The window title: the manual title when non-empty, else the first
    /// content line (trimmed), else the localized "Untitled Note" fallback.
    /// Never truncates — the titlebar applies its own system ellipsis.
    public static func deriveWindowTitle(noteTitle: String?, firstLine: String) -> String {
        if let noteTitle {
            let trimmed = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let line = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if !line.isEmpty { return line }
        return String(localized: "note.window.untitledTitle", defaultValue: "Untitled Note")
    }

    /// The first line of a canonical rich-text document (FR-003 title
    /// source). Empty when the document has no content.
    public static func firstLine(of document: RichTextDocument) -> String {
        guard let newline = document.text.firstIndex(of: "\n") else {
            return document.text
        }
        return String(document.text[..<newline])
    }

    /// The first meaningful content line across the note's blocks (004
    /// FR-003 — mirrors `NoteSummary` extraction semantics: first
    /// non-empty rich-text/todo/code line, else file display name /
    /// caption / "Screenshot" / "Image").
    public static func firstMeaningfulLine(blocks: [Block]) -> String {
        let ordered = blocks.sorted { $0.sortKey < $1.sortKey }
        for block in ordered {
            switch block.payload {
            case .richText(let doc):
                let line = firstLine(of: doc).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { return line }
            case .todo(let payload):
                let line = firstLine(of: payload.richText).trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty { return line }
            case .code(let payload):
                let line = payload.text
                    .split(whereSeparator: \.isNewline)
                    .first
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
                if !line.isEmpty { return line }
            case .fileReference(let payload):
                if !payload.displayName.isEmpty { return payload.displayName }
            case .screenshot(let payload):
                if let caption = payload.caption, !caption.isEmpty { return caption }
                return String(localized: "Screenshot")
            case .image(let payload):
                if let caption = payload.caption, !caption.isEmpty { return caption }
                return String(localized: "Image")
            }
        }
        return ""
    }

    // MARK: Block ordering (004 修复 2026-08-14, P0)

    /// The note's blocks in canonical order: ascending sortKey, ties broken
    /// by block id (deterministic). The host's in-memory `blocks` array
    /// already IS this order (repository `ORDER BY sortKey ASC` + insertion
    /// positions) — this helper is the single ordering source for consumers
    /// that need an explicit ordering (e.g. tail continuation), never a
    /// per-view re-sort.
    public static func orderedBlocks(_ blocks: [Block]) -> [Block] {
        blocks.sorted {
            $0.sortKey != $1.sortKey
                ? $0.sortKey < $1.sortKey
                : $0.id.uuidString < $1.id.uuidString
        }
    }

    // MARK: Insertion target resolution (004 FR-010/Q4, contracts §5)

    /// Resolves where a window-level insertion lands:
    /// 1. caret in a rich-text block → `.caretSplit` at the caret offset;
    /// 2. a focused special block → `.afterBlock`;
    /// 3. otherwise → `.append`.
    public static func resolveInsertionTarget(
        blocks: [Block],
        context: InsertionContext
    ) -> InsertionTarget {
        if let caretBlockId = context.caretBlockId,
           let offset = context.caretOffset,
           blocks.contains(where: { $0.id == caretBlockId && $0.kind == .richText }) {
            return .caretSplit(blockId: caretBlockId, offset: offset)
        }
        if let blockId = context.focusedSpecialBlockId,
           blocks.contains(where: { $0.id == blockId && $0.kind != .richText }) {
            return .afterBlock(blockId: blockId)
        }
        return .append
    }

    // MARK: Rich-text block split (004 FR-010/R3, data-model.md §4.3)

    /// Converts an NSTextView caret offset (UTF-16 code units) to a Unicode
    /// scalar offset — canonical documents and `splitRichTextBlock` use
    /// scalar offsets. Fixes CJK/emoji caret splits landing on the wrong
    /// character (004 修复 2026-08-13).
    public static func scalarOffset(fromUTF16 utf16Offset: Int, in text: String) -> Int {
        let ns = text as NSString
        let clamped = min(max(utf16Offset, 0), ns.length)
        guard let range = Range(NSRange(location: 0, length: clamped), in: text) else {
            return 0
        }
        return text[range].unicodeScalars.count
    }

    /// Splits a canonical rich-text document at a scalar offset. Run marks
    /// and links are preserved on both sides; a run crossing the offset is
    /// split into two runs with identical attributes. Paragraph boundaries
    /// are re-derived per side (each side becomes its own block).
    public static func splitRichTextBlock(
        payload: RichTextDocument,
        offset: Int
    ) -> (leading: RichTextDocument, trailing: RichTextDocument) {
        let scalars = Array(payload.text.unicodeScalars)
        let split = min(max(offset, 0), scalars.count)

        let leadingText = String(String.UnicodeScalarView(scalars[0..<split]))
        let trailingText = String(String.UnicodeScalarView(scalars[split..<scalars.count]))

        var leadingRuns: [RichTextRun] = []
        var trailingRuns: [RichTextRun] = []

        for paragraph in payload.paragraphs {
            for run in paragraph.runs {
                if run.endScalar <= split {
                    leadingRuns.append(run)
                } else if run.startScalar >= split {
                    trailingRuns.append(RichTextRun(
                        startScalar: run.startScalar - split,
                        endScalar: run.endScalar - split,
                        marks: run.marks,
                        link: run.link,
                        hardBreak: run.hardBreak
                    ))
                } else {
                    // The run crosses the split — divide its attributes.
                    leadingRuns.append(RichTextRun(
                        startScalar: run.startScalar,
                        endScalar: split,
                        marks: run.marks,
                        link: run.link,
                        hardBreak: false
                    ))
                    trailingRuns.append(RichTextRun(
                        startScalar: 0,
                        endScalar: run.endScalar - split,
                        marks: run.marks,
                        link: run.link,
                        hardBreak: run.hardBreak
                    ))
                }
            }
        }

        return (
            leading: rebuild(text: leadingText, runs: leadingRuns),
            trailing: rebuild(text: trailingText, runs: trailingRuns)
        )
    }

    /// Trims the trailing empty paragraphs (trailing newline/whitespace
    /// scalars) from a canonical rich-text document. Runs and links are
    /// re-split at the trimmed offset, so marks survive on the remaining
    /// text. Feeds the caret-at-end insertion path: the empty paragraph the
    /// caret sat in is CONSUMED, never materialized as an empty block
    /// (004 修复 2026-08-13).
    public static func trimmingTrailingEmptyLines(_ document: RichTextDocument) -> RichTextDocument {
        let scalars = Array(document.text.unicodeScalars)
        var end = scalars.count
        while end > 0, CharacterSet.whitespacesAndNewlines.contains(scalars[end - 1]) {
            end -= 1
        }
        guard end < scalars.count else { return document }
        return splitRichTextBlock(payload: document, offset: end).leading
    }

    // MARK: Opacity formatting (004 FR-009, data-model.md §4.4)

    /// Formats an opacity value as a complete "NN%" string — never
    /// truncated, never fraction-padded ("100%", "60%", "40%").
    public static func formatOpacityPercent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    /// Step-exact opacity clamp (0.00–1.00, 0.05 steps — 004 Q8). Integer-
    /// percent arithmetic so every step equals the exact Double literal
    /// (e.g. `clampedOpacity(0.60) == 0.60`) — Domain's
    /// `OpacityBounds.clamped` multiplies the inexact `0.05` step and
    /// returns 0.6000000000000001.
    public static func clampedOpacity(_ value: Double) -> Double {
        let rawPercent = Int((value * 100).rounded())
        let clamped = min(max(rawPercent, 0), 100)
        let stepped = Int((Double(clamped) / 5.0).rounded()) * 5
        return Double(min(max(stepped, 0), 100)) / 100.0
    }

    // MARK: Toolbar visibility priority (004 FR-015a, data-model.md §4.5)

    /// The fixed semantic priority mapping (004 T065, 2026-08-13 user
    /// feedback): pin + insert → `.high` (last into the overflow — the
    /// narrow state keeps the two "primary" commands visible), appearance +
    /// more → `.standard` (first into the system overflow, whose submenu
    /// forms carry the low-frequency actions — no product-level "…" item
    /// trapped inside the system "»").
    public static func toolbarVisibilityPriority(
        itemIdentifier: String
    ) -> NSToolbarItem.VisibilityPriority {
        switch itemIdentifier {
        case NoteToolbarSpec.pinIdentifier, NoteToolbarSpec.insertIdentifier:
            return .high
        default:
            return .standard
        }
    }

    // MARK: Palette storage mapping (001 FR-032 semantics, shared by the
    // appearance panel + menus — migrated from NoteControlsView)

    /// Applies a palette key to a note via the FR-032 storage mapping:
    /// built-in keys map to their Domain equivalent; peach is preserved as
    /// a custom color with the palette's designed light value. Custom
    /// colors are never entered.
    public static func note(applyingPaletteKey key: NotePaletteKey, to note: Note) -> Note {
        var updated = note
        switch key {
        case .yellow:   updated.colorKey = .yellow
        case .peach:    updated.colorKey = .custom; updated.customColor = "#FFC9A8"
        case .pink:     updated.colorKey = .pink
        case .green:    updated.colorKey = .green
        case .blue:     updated.colorKey = .blue
        case .lavender: updated.colorKey = .purple
        case .gray:     updated.colorKey = .gray
        }
        if key != .peach { updated.customColor = nil }
        return updated
    }

    /// The palette key a note is currently showing, or nil for custom
    /// colors (which never enter the palette — FR-032).
    public static func paletteKey(for note: Note) -> NotePaletteKey? {
        NotePalette.paletteKey(for: note.colorKey)
    }

    /// FR-008 "restore sensible defaults": the default palette color at
    /// full opacity.
    public static func resetAppearance(of note: Note) -> Note {
        var updated = note
        updated.colorKey = .yellow
        updated.customColor = nil
        updated.transparency = 1.0
        return updated
    }

    /// 004 T069 (2026-08-13): composes a note for an appearance change from
    /// the ORIGINAL base note + the CURRENT local appearance state. The
    /// panel must never read appearance values back from a stale `note`
    /// snapshot (the slider knob then refuses to follow the mouse and the
    /// "NN%" label freezes until the popover is reopened).
    public static func composeAppearance(
        base: Note,
        colorKey: NoteColorKey,
        customColor: String?,
        transparency: Double
    ) -> Note {
        var updated = base
        updated.colorKey = colorKey
        updated.customColor = customColor
        updated.transparency = clampedOpacity(transparency)
        return updated
    }

    // MARK: - Internals

    /// Rebuilds a split document side: re-derives paragraph boundaries
    /// (newline-split, scalar offsets) and assigns runs by containment —
    /// mirroring `RichTextView.Coordinator.canonicalDocument`.
    private static func rebuild(text: String, runs: [RichTextRun]) -> RichTextDocument {
        let scalars = Array(text.unicodeScalars)
        let sorted = runs.sorted { lhs, rhs in
            lhs.startScalar != rhs.startScalar
                ? lhs.startScalar < rhs.startScalar
                : lhs.endScalar < rhs.endScalar
        }
        // Merge adjacent runs with identical attributes (enumerateAttributes
        // coalesces them anyway; keeping them merged keeps documents small).
        var merged: [RichTextRun] = []
        for run in sorted {
            if let last = merged.last, last.endScalar == run.startScalar,
               last.marks == run.marks, last.link == run.link, last.hardBreak == run.hardBreak {
                merged[merged.count - 1] = RichTextRun(
                    startScalar: last.startScalar,
                    endScalar: run.endScalar,
                    marks: run.marks,
                    link: run.link,
                    hardBreak: run.hardBreak
                )
            } else {
                merged.append(run)
            }
        }

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
            let contained = merged.filter {
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
}

// MARK: - RichTextMarkApplier (004 FR-012/FR-053; US5)

/// Applies supported marks to an NSTextView — the single formatting entry
/// point. NSTextView is the formatting authority; SwiftUI holds no mark
/// state copy. Selection path edits the textStorage; the no-selection path
/// edits typingAttributes (applies to subsequent input).
public enum RichTextMarkApplier {

    /// Applies (or toggles off) the given marks. Returns `true` when any
    /// change was applied.
    @MainActor
    @discardableResult
    public static func applyMarks(_ marks: Set<RichTextMark>, to textView: NSTextView) -> Bool {
        // IME guard (FR-063): never apply during composition.
        guard !textView.hasMarkedText() else { return false }
        let range = textView.selectedRange()
        if range.length > 0 {
            return applyToRange(range, marks: marks, textView: textView)
        }
        applyToTypingAttributes(marks, textView: textView)
        return true
    }

    @MainActor
    private static func applyToRange(_ range: NSRange, marks: Set<RichTextMark>, textView: NSTextView) -> Bool {
        guard let storage = textView.textStorage else { return false }
        var changed = false
        for mark in marks {
            switch mark {
            case .bold, .italic:
                changed = applyFontTrait(mark, range: range, storage: storage) || changed
            case .inlineCode:
                changed = applyInlineCode(range: range, storage: storage) || changed
            case .underline:
                changed = toggleAttribute(.underlineStyle, range: range, storage: storage) || changed
            case .strikethrough:
                changed = toggleAttribute(.strikethroughStyle, range: range, storage: storage) || changed
            }
        }
        return changed
    }

    /// The obliqueness applied as synthesized italic for families without
    /// an italic face (CJK PingFang has none) — TextKit renders the skew
    /// natively, unlike NSFont matrix synthesis which NSFont silently
    /// drops (verified 2026-08-13).
    static let synthesizedItalicObliqueness: Double = 0.25

    @MainActor
    private static func applyToTypingAttributes(_ marks: Set<RichTextMark>, textView: NSTextView) {
        var attributes = textView.typingAttributes
        let base = (attributes[.font] as? NSFont)
            ?? textView.font
            ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for mark in marks {
            switch mark {
            case .bold:
                attributes[.font] = synthesizedFont(base, adding: .bold)
            case .italic:
                let target = synthesizedFont(base, adding: .italic)
                attributes[.font] = target
                if hasTrait(.italic, in: target) {
                    attributes[.obliqueness] = nil
                } else {
                    attributes[.obliqueness] = synthesizedItalicObliqueness
                }
            case .inlineCode:
                attributes[.font] = NSFont.monospacedSystemFont(ofSize: base.pointSize, weight: .regular)
            case .underline:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .strikethrough:
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
        }
        textView.typingAttributes = attributes
    }

    /// Adds a symbolic trait via NSFontManager (true faces only). For
    /// families without the face this returns a font without the trait —
    /// callers fall back to `.obliqueness` for italic (see
    /// `synthesizedItalicObliqueness`).
    static func synthesizedFont(_ font: NSFont, adding trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        return NSFontManager.shared.convert(font, toHaveTrait: mask)
    }

    /// Removes a symbolic trait (idempotent — unchanged when absent).
    static func synthesizedFont(_ font: NSFont, removing trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let mask: NSFontTraitMask = trait == .bold ? .boldFontMask : .italicFontMask
        return NSFontManager.shared.convert(font, toNotHaveTrait: mask)
    }

    @MainActor
    private static func applyFontTrait(_ mark: RichTextMark, range: NSRange, storage: NSTextStorage) -> Bool {
        var changed = false
        let trait: NSFontDescriptor.SymbolicTraits = mark == .bold ? .bold : .italic
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let hasOblique = mark == .italic && storage.attribute(.obliqueness, at: subrange.location, effectiveRange: nil) != nil
            if hasTrait(trait, in: font) || hasOblique {
                // Toggle off: revert the font AND clear synthesized obliqueness.
                storage.addAttribute(.font, value: synthesizedFont(font, removing: trait), range: subrange)
                if mark == .italic { storage.removeAttribute(.obliqueness, range: subrange) }
            } else {
                let target = synthesizedFont(font, adding: trait)
                storage.addAttribute(.font, value: target, range: subrange)
                // 004 修复: no italic face (CJK) → synthesized obliqueness,
                // so ⌘I visibly applies instead of silently no-opping.
                if mark == .italic, !hasTrait(.italic, in: target) {
                    storage.addAttribute(.obliqueness, value: synthesizedItalicObliqueness, range: subrange)
                }
            }
            changed = true
        }
        return changed
    }

    /// Whether the font carries the trait — italic also counts when the
    /// font is a synthesized oblique (descriptor matrix non-identity).
    static func hasTrait(_ trait: NSFontDescriptor.SymbolicTraits, in font: NSFont) -> Bool {
        if font.fontDescriptor.symbolicTraits.contains(trait) { return true }
        if trait == .italic, let matrix = font.fontDescriptor.matrix, matrix != .identity { return true }
        return false
    }

    @MainActor
    private static func applyInlineCode(range: NSRange, storage: NSTextStorage) -> Bool {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let font = (value as? NSFont) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            storage.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular), range: subrange)
        }
        return range.length > 0
    }

    /// Toggles an integer attribute (underline/strikethrough) on/off.
    @MainActor
    private static func toggleAttribute(_ key: NSAttributedString.Key, range: NSRange, storage: NSTextStorage) -> Bool {
        guard range.length > 0 else { return false }
        let existing = storage.attribute(key, at: range.location, effectiveRange: nil) != nil
        if existing {
            storage.removeAttribute(key, range: range)
        } else {
            storage.addAttribute(key, value: NSUnderlineStyle.single.rawValue, range: range)
        }
        return true
    }
}
