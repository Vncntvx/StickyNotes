import AppKit
import SwiftUI
import Domain
import Persistence

// MARK: - LibraryToolbar (003 T018/T019 spike → US1)
//
// T018 spike decision (2026-08-09): the MenuBarExtra window hosts an
// AppKit `NSToolbar` attached via the existing `MenuBarLibraryWindowProbe`
// (方案 A). Acceptance criteria recorded in plan.md §14/§15:
// - items display in the single native toolbar row (FR-002)
// - overflow: system NSToolbar overflow behavior (FR-070) — secondary
//   items move into the overflow menu as the window narrows
// - keyboard: native toolbar items are keyboard-reachable; Tab/Shift-Tab
//   focus order verified in the manual QA matrix (CHK004)
// - click-outside-close and 4 pt/left-edge positioning do NOT regress
//   (FR-001/001a — `MenuBarLibraryWindow.positionLibraryWindow` is
//   untouched; the toolbar attaches in the same probe)
//
// The toolbar items:
// - New Note (⌘N, SF Symbol)
// - Search (`NSSearchField` item — native search, FR-003)
// - Sort (popup, 001 FR-022 modes — secondary weight)
// - Destination (Notes/Trash compact group, FR-005 (a))
//
// Item actions call back into the SwiftUI model through closures (the
// same `LibraryModel` methods the CommandGroup actions reuse).

@MainActor
final class LibraryToolbarDelegate: NSObject, NSToolbarDelegate {
    enum Item {
        static let newNote = NSToolbarItem.Identifier("library.newNote")
        static let search = NSToolbarItem.Identifier("library.search")
        static let sort = NSToolbarItem.Identifier("library.sort")
        static let destination = NSToolbarItem.Identifier("library.destination")
        static let flexibleSpace = NSToolbarItem.Identifier.flexibleSpace
    }

    private let model: LibraryModel
    private let openNote: (UUID) -> Void
    private var searchField: NSSearchField?
    private var sortPopup: NSPopUpButton?
    private var destinationControl: NSSegmentedControl?
    private var newNoteItem: NSToolbarItem?
    private var searchItem: NSToolbarItem?
    private var sortItem: NSToolbarItem?
    private var destinationItem: NSToolbarItem?

    init(model: LibraryModel, openNote: @escaping (UUID) -> Void) {
        self.model = model
        self.openNote = openNote
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.newNote, Item.search, .flexibleSpace, Item.sort, Item.destination]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.newNote, Item.search, Item.sort, Item.destination, .flexibleSpace]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case Item.newNote:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let button = NSButton(
                image: NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New Note")!,
                target: self,
                action: #selector(createNote)
            )
            button.bezelStyle = .texturedRounded
            button.toolTip = String(localized: "Create a new note")
            button.setAccessibilityLabel(String(localized: "New Note"))
            item.view = button
            item.label = String(localized: "New Note")
            item.toolTip = String(localized: "Create a new note")
            item.isBordered = true
            newNoteItem = item
            return item
        case Item.search:
            let field = NSSearchField()
            field.placeholderString = String(localized: "Search notes")
            field.target = self
            field.action = #selector(searchChanged(_:))
            field.sendsSearchStringImmediately = true
            field.setAccessibilityLabel(String(localized: "Search notes"))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = field
            item.label = String(localized: "Search")
            item.isBordered = true
            item.visibilityPriority = .standard
            searchField = field
            searchItem = item
            return item
        case Item.sort:
            let popup = NSPopUpButton()
            popup.addItem(withTitle: String(localized: "Recently Modified"))
            popup.addItem(withTitle: String(localized: "Created"))
            popup.addItem(withTitle: String(localized: "Title"))
            popup.addItem(withTitle: String(localized: "Manual"))
            popup.target = self
            popup.action = #selector(sortChanged(_:))
            popup.setAccessibilityLabel(String(localized: "Sort"))
            popup.menu?.items[0].representedObject = NoteSortKey.modified.rawValue
            popup.menu?.items[1].representedObject = NoteSortKey.created.rawValue
            popup.menu?.items[2].representedObject = NoteSortKey.title.rawValue
            popup.menu?.items[3].representedObject = NoteSortKey.manual.rawValue
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = popup
            item.label = String(localized: "Sort")
            item.isBordered = true
            sortPopup = popup
            sortItem = item
            return item
        case Item.destination:
            let control = NSSegmentedControl(
                labels: [String(localized: "Notes"), String(localized: "Trash")],
                trackingMode: .selectOne,
                target: self,
                action: #selector(destinationChanged(_:))
            )
            control.selectedSegment = 0
            control.setAccessibilityLabel(String(localized: "Notes / Trash destination"))
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.view = control
            item.label = String(localized: "Destination")
            item.isBordered = true
            destinationControl = control
            destinationItem = item
            return item
        default:
            return nil
        }
    }

    // MARK: Actions (call through to the SwiftUI model)

    @objc private func createNote() {
        Task { @MainActor in
            if let id = await model.createBlankNote() {
                openNote(id)
            }
        }
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        model.setSearchQuery(sender.stringValue)
    }

    @objc private func sortChanged(_ sender: NSPopUpButton) {
        guard let raw = sender.selectedItem?.representedObject as? String,
              let key = NoteSortKey(rawValue: raw) else { return }
        model.setSort(key)
    }

    @objc private func destinationChanged(_ sender: NSSegmentedControl) {
        model.setScope(sender.selectedSegment == 0 ? .library : .trash)
    }

    /// Consumes a search-focus request (⌘F / searchAll): makes the search
    /// field first responder.
    func focusSearch() {
        searchField?.window?.makeFirstResponder(searchField)
    }

    /// Synchronizes the toolbar controls with the model (scope switches
    /// from menus/destination, sort changes, search resets).
    func syncState() {
        destinationControl?.selectedSegment = model.scope == .library ? 0 : 1
        let sortIndex: Int
        switch model.sort {
        case .modified: sortIndex = 0
        case .created:  sortIndex = 1
        case .title:    sortIndex = 2
        case .manual:   sortIndex = 3
        }
        sortPopup?.selectItem(at: sortIndex)
        searchField?.stringValue = model.searchQuery
    }
}

/// Attaches the native library toolbar to the hosting window (attached via
/// the existing window probe — FR-001a positioning untouched).
@MainActor
enum LibraryToolbar {
    private static var delegateRegistry: [ObjectIdentifier: LibraryToolbarDelegate] = [:]

    /// Attaches the toolbar to the window (idempotent). Returns the
    /// delegate (retained by the registry keyed on the window).
    static func attach(to window: NSWindow, model: LibraryModel, openNote: @escaping (UUID) -> Void) -> LibraryToolbarDelegate? {
        let key = ObjectIdentifier(window)
        if let existing = delegateRegistry[key] {
            return existing
        }
        let delegate = LibraryToolbarDelegate(model: model, openNote: openNote)
        let toolbar = NSToolbar(identifier: "library.toolbar")
        toolbar.delegate = delegate
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        window.toolbar = toolbar
        delegateRegistry[key] = delegate
        return delegate
    }

    static func delegate(for window: NSWindow) -> LibraryToolbarDelegate? {
        delegateRegistry[ObjectIdentifier(window)]
    }
}
