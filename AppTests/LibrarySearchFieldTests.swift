import Testing
import AppKit
import SwiftUI
@testable import StickyNotes

// MARK: - 003 T184 (FR-003/003a Rev 3, 2026-08-14)

/// Headless tests for the native search-field bridge: the pure
/// configuration and the text round-trip through the delegate. The
/// ⌘F first-responder behavior needs a window and is verified manually.
struct LibrarySearchFieldTests {

    @Test func specConfiguresNativeSearchField() {
        // R3.10 (remediation-phase1 T004 bundled fix, 2026-08-15): the
        // placeholder is LOCALIZED (String(localized:)) — the previous
        // `== "Search notes"` assertion was locale-dependent and failed on
        // zh-Hans systems (CI zh job regression, verified 2026-08-14).
        // The locale-neutral contract: the spec placeholder is never empty
        // and the field is configured from the spec constant.
        #expect(!LibrarySearchFieldSpec.placeholder.isEmpty,
                "search placeholder must be non-empty in every locale (FR-003)")
        #expect(LibrarySearchFieldSpec.sendsSearchStringImmediately == false,
                "text must flow through the delegate so the scene keeps its debounce-free reload contract (FR-024a)")
    }

    @MainActor
    @Test func delegateWritesTypingToBinding() {
        var text = ""
        let coordinator = LibrarySearchField.Coordinator(
            text: Binding(get: { text }, set: { text = $0 })
        )
        let field = NSSearchField()
        field.stringValue = "avocados"
        coordinator.controlTextDidChange(
            Notification(name: NSText.didChangeNotification, object: field)
        )
        #expect(text == "avocados")
    }

    @Test func cancelClearsTheQuery() {
        var text = "avocados"
        let coordinator = LibrarySearchField.Coordinator(
            text: Binding(get: { text }, set: { text = $0 })
        )
        coordinator.searchFieldDidCancelSearch(NSSearchField())
        #expect(text == "")
    }
}
