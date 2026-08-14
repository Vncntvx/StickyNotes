import SwiftUI
import AppKit

// MARK: - LibrarySearchField (003 T184, FR-003/003a Rev 3; 2026-08-14)
//
// Per tasks.md T184 and spec FR-003 (Rev 3): the search control is the
// AppKit NATIVE search field (`NSSearchField`) bridged through
// NSViewRepresentable — system search icon, clear button, native behaviors
// — replacing the hand-drawn `TextField(.plain)` + quaternary rounded
// background. The scene keeps the search contract unchanged: the binding
// writes `model.searchQuery` and the scene's `.onChange` performs the
// debounce-free reload (FR-024/024a). ⌘F / `stickynotes://search` route
// through `model.searchFocusRequested` (FR-003a): the flipped flag makes
// the field first responder, then `onFocusConsumed` resets it — the same
// consume-once contract the SwiftUI `@FocusState` path had.

/// Pure configuration for the native search field — asserted by
/// `LibrarySearchFieldTests` (project pattern: views consult, tests assert).
enum LibrarySearchFieldSpec {
    /// The placeholder prompt (FR-003 prompt semantics unchanged).
    static let placeholder = String(localized: "Search notes")
    /// Immediate search OFF: text changes flow through the delegate so the
    /// scene's debounce-free reload contract is preserved (FR-024a) — the
    /// field never runs its own action-based reload.
    static let sendsSearchStringImmediately = false
}

/// The native search field (FR-003/003a Rev 3).
struct LibrarySearchField: NSViewRepresentable {
    /// The search text — bound to `model.searchQuery`.
    @Binding var text: String
    /// A ⌘F / deep-link focus request; when flipped true the field becomes
    /// first responder and `onFocusConsumed` resets the model flag.
    var focusRequested: Bool
    /// Consumes the focus request after the field took first responder.
    var onFocusConsumed: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = LibrarySearchFieldSpec.placeholder
        field.sendsSearchStringImmediately = LibrarySearchFieldSpec.sendsSearchStringImmediately
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        // Only rewrite when they differ — writing during editing would
        // reset the field's selection/cursor.
        if field.stringValue != text {
            field.stringValue = text
        }
        // FR-003a: consume the model's focus request. The window is the
        // MenuBarExtra window (the scene exists only while it is open).
        if focusRequested {
            field.window?.makeFirstResponder(field)
            onFocusConsumed()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        /// Typing updates the binding immediately (FR-024a: the scene's
        /// reload is debounce-free).
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            text = field.stringValue
        }

        /// The clear (cancel) button: empty the query explicitly.
        func searchFieldDidCancelSearch(_ sender: NSSearchField) {
            text = ""
        }
    }
}
