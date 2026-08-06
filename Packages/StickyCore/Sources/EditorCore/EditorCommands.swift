import Foundation
import Domain

// MARK: - EditorCommands (T074)
//
// Per tasks.md T074: "Implement editor command layer over `UndoManager`
// (cursor placement after conversion)."
//
// The command layer wraps the MarkdownTransformer's pure decisions in
// concrete editor commands that:
//   1. Group the conversion + delimiter removal as ONE undo group (FR-077).
//   2. Place the cursor at the transform's computed offset.
//   3. Cache the pre-transform text so single-Undo restores the exact
//      source delimiters.
//
// This is the framework-free core: it doesn't depend on AppKit's
// UndoManager directly (so it's testable). The App layer supplies a thin
// `UndoGrouping` adapter that bridges to the real UndoManager.

/// The minimal UndoManager surface the command layer needs. The App layer
/// bridges to NSUndoManager / SwiftUI's environment UndoManager.
public protocol EditorUndoGrouping: Sendable {
    /// Begins an undo group. All subsequent registrations belong to one undo.
    func beginUndoGrouping()
    /// Registers an inverse operation that restores `originalText` at the
    /// given line/document scope. The App layer calls this to register the
    /// "single Undo restores exact source" inverse.
    func registerRestore(originalText: String, scope: EditorScope)
    /// Ends the undo group. Subsequent registrations start a new group.
    func endUndoGrouping()
}

/// The scope a transform applies to.
public enum EditorScope: Sendable, Equatable {
    /// A line-level transform scoped to one line (by line index).
    case line(index: Int)
    /// An inline transform scoped to the whole document (the text + a
    /// scalar range).
    case document
}

/// The editor command layer. Stateless except for the cached pre-transform
/// text (needed for single-Undo restoration). The App layer owns one
/// instance per open note editor.
public final class EditorCommands: @unchecked Sendable {
    private let undoGrouping: EditorUndoGrouping

    public init(undoGrouping: EditorUndoGrouping) {
        self.undoGrouping = undoGrouping
    }

    // MARK: - Line-level command

    /// Applies a line-level Markdown transform as one undo group. Returns
    /// the new line text + cursor offset. The caller (the App's
    /// RichTextAdapter) updates the text view and places the cursor.
    public func applyLineLevel(
        _ transform: MarkdownLineTransform,
        toLine line: String,
        lineIndex: Int
    ) -> (newLine: String, cursorOffset: Int) {
        let original = line
        let (newLine, cursor) = MarkdownTransformer.applyLineLevel(transform, toLine: line)

        // Group: conversion + delimiter removal = ONE undo (FR-077).
        undoGrouping.beginUndoGrouping()
        undoGrouping.registerRestore(originalText: original, scope: .line(index: lineIndex))
        undoGrouping.endUndoGrouping()

        return (newLine, cursor)
    }

    // MARK: - Inline command

    /// Applies an inline Markdown transform as one undo group. Returns the
    /// new document text + cursor offset.
    public func applyInline(
        _ transform: MarkdownInlineTransform,
        range: MarkdownInlineRange,
        to text: String
    ) -> (newText: String, cursorOffset: Int) {
        let original = text
        let (newText, cursor) = MarkdownTransformer.applyInline(transform, range: range, to: text)

        undoGrouping.beginUndoGrouping()
        undoGrouping.registerRestore(originalText: original, scope: .document)
        undoGrouping.endUndoGrouping()

        return (newText, cursor)
    }

    // MARK: - Decision orchestration

    /// Inspects a line and, if a line-level transform should fire, applies
    /// it as one undo group. Returns the result + the transform that was
    /// applied (or `.none`). The `hasIMEComposition` flag comes from the
    /// App's TextEditor marked-range state.
    public func maybeTransformLine(
        line: String,
        lineIndex: Int,
        insideCodeBlock: Bool,
        hasIMEComposition: Bool
    ) -> (transform: MarkdownTransform, newLine: String?, cursorOffset: Int?) {
        let decision = MarkdownTransformer.decideLineLevel(
            line: line,
            insideCodeBlock: insideCodeBlock,
            hasIMEComposition: hasIMEComposition
        )
        switch decision {
        case .none:
            return (.none, nil, nil)
        case .lineLevel(let lt):
            let (newLine, cursor) = applyLineLevel(lt, toLine: line, lineIndex: lineIndex)
            return (.lineLevel(lt), newLine, cursor)
        case .inline:
            return (.none, nil, nil)  // not a line-level path
        }
    }

    /// Inspects the document at the cursor and, if an inline transform
    /// should fire, applies it as one undo group.
    public func maybeTransformInline(
        text: String,
        cursorScalarOffset: Int,
        insideCodeBlock: Bool,
        hasIMEComposition: Bool
    ) -> (transform: MarkdownTransform, newText: String?, cursorOffset: Int?) {
        let decision = MarkdownTransformer.decideInline(
            text: text,
            cursorScalarOffset: cursorScalarOffset,
            insideCodeBlock: insideCodeBlock,
            hasIMEComposition: hasIMEComposition
        )
        switch decision {
        case .none:
            return (.none, nil, nil)
        case .inline(let mark, let range):
            let (newText, cursor) = applyInline(mark, range: range, to: text)
            return (.inline(mark, range), newText, cursor)
        case .lineLevel:
            return (.none, nil, nil)  // not an inline path
        }
    }
}
