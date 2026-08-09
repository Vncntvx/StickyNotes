import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Domain

// MARK: - NoteToolbarController (004 T016, FR-001/FR-006/FR-015)
//
// Per plan.md §3 and contracts §1-2: ONE AppKit NSToolbar per note window,
// created by `NoteWindowCoordinator.open(noteId:)`, held in
// `toolbars[noteId]`, released together with the window delegate. The
// toolbar is product-fixed (FR-015c/Q3: no user customization; the system
// overflow chevron handles narrow widths) with four items:
//
//   pin (.high priority — last into the overflow; FR-015a/Q2)
//   appearance / insert / more (.standard — first into the overflow)
//
// Each item has a `menuFormRepresentation` pointing at the SAME action as
// its button form (single implementation, multiple presentations —
// FR-011). The controller observes the host's appearance fields
// (Observation, event-driven — no polling) and refreshes item states.
//
// Liquid Glass (FR-021/FR-022/FR-023): the toolbar, its buttons
// (`.glass` bezel), menus and popover are ALL system-provided glass — the
// controller adds no custom glass. The only custom glass surface in the
// feature is the contextual format row (US5), rendered in SwiftUI.

@MainActor
final class NoteToolbarController: NSObject, NSToolbarDelegate {
    private let noteId: UUID
    /// Weak on purpose (plan §2.3 retain chain: coordinator → controller →
    /// weak references outward; no cycles).
    private weak var coordinator: NoteWindowCoordinator?
    private weak var host: NoteWindowHostModel?

    let toolbar: NSToolbar
    /// Item cache: identifiers → items. Items are built ONCE per window
    /// lifecycle and never rebuilt during resize (plan §9.5).
    private var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    /// The appearance panel popover (closed on teardown; FR-015c — no
    /// persistence of open state).
    private var appearancePopover: NSPopover?
    private var isTearingDown = false

    init(noteId: UUID, host: NoteWindowHostModel, coordinator: NoteWindowCoordinator) {
        self.noteId = noteId
        self.host = host
        self.coordinator = coordinator
        self.toolbar = NSToolbar(identifier: NSToolbar.Identifier(NoteToolbarSpec.toolbarIdentifier))
        super.init()
        toolbar.delegate = self
        // FR-015c/Q3: fixed toolbar — no user customization palette.
        toolbar.allowsUserCustomization = false
        toolbar.displayMode = .iconOnly
        toolbar.sizeMode = .regular
        // Item sets come from the delegate methods
        // (`toolbarDefaultItemIdentifiers:`/`toolbarAllowedItemIdentifiers:`).
        startObserving()
    }

    deinit {
        isTearingDown = true
    }

    /// Closes transient UI and stops observation (called on the same
    /// release path as the window delegate — contracts §1).
    func teardown() {
        isTearingDown = true
        appearancePopover?.close()
        appearancePopover = nil
        items.removeAll()
    }

    /// Initial state sync (contracts §1 — called right after the toolbar is
    /// attached to the window).
    func syncState() {
        refreshFromHost()
    }

    // MARK: - Observation (plan §2.3: event-driven, no polling)

    /// Re-registers observation after every host-appearance change. No
    /// timers — idle windows do zero work (001 SC-006).
    private func startObserving() {
        guard let host else { return }
        func register() {
            guard !isTearingDown else { return }
            withObservationTracking {
                _ = host.note?.alwaysOnTop
                _ = host.note?.colorKey
                _ = host.note?.customColor
                _ = host.note?.transparency
            } onChange: { [weak self] in
                let owner = self
                Task { @MainActor in
                    owner?.refreshFromHost()
                    owner?.startObserving()
                }
            }
        }
        register()
    }

    /// Refreshes item states from the host (pin state; appearance fields).
    func refreshFromHost() {
        guard let note = host?.note else { return }
        syncPinState(alwaysOnTop: note.alwaysOnTop)
        // FR-003: title derivation is host-driven (the content layer owns
        // the title field); the window title follows.
        coordinator?.updateWindowTitle(noteId: noteId)
    }

    // MARK: - NSToolbarDelegate

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        if let cached = items[itemIdentifier] { return cached }
        let item: NSToolbarItem
        switch itemIdentifier.rawValue {
        case NoteToolbarSpec.pinIdentifier:
            item = makePinItem()
        case NoteToolbarSpec.appearanceIdentifier:
            item = makeAppearanceItem()
        case NoteToolbarSpec.insertIdentifier:
            item = makeInsertItem()
        case NoteToolbarSpec.moreIdentifier:
            item = makeMoreItem()
        default:
            return nil
        }
        items[itemIdentifier] = item
        return item
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        NoteToolbarSpec.itemIdentifierStrings.map { NSToolbarItem.Identifier($0) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        NoteToolbarSpec.itemIdentifierStrings.map { NSToolbarItem.Identifier($0) }
    }

    // MARK: - Item factories

    /// A standard toolbar button view (glass on macOS 26+; the deployment
    /// floor is 26, but the defensive `.toolbar` fallback mirrors the
    /// plan's compatibility matrix).
    private func makeToolbarButton(systemImage: String, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .toolbar
        if #available(macOS 26.0, *) {
            button.bezelStyle = .glass
        }
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.target = self
        button.action = action
        button.setButtonType(.momentaryPushIn)
        return button
    }

    /// A toolbar item with a plain-button view + overflow menu form.
    private func toolbarItem(
        identifier: String,
        button: NSButton,
        label: String,
        tooltip: String,
        menuForm: NSMenuItem,
        priority: NSToolbarItem.VisibilityPriority
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
        item.label = label
        item.paletteLabel = label
        item.toolTip = tooltip
        item.view = button
        item.menuFormRepresentation = menuForm
        item.visibilityPriority = priority
        return item
    }

    // MARK: Pin (004 T020, FR-007/FR-015a)

    private func makePinItem() -> NSToolbarItem {
        let button = makeToolbarButton(systemImage: "pin", action: #selector(pinAction(_:)))
        button.setButtonType(.toggle)
        let item = toolbarItem(
            identifier: NoteToolbarSpec.pinIdentifier,
            button: button,
            label: String(localized: "Always on Top"),
            tooltip: String(localized: "Always on Top"),
            menuForm: makePinMenuItem(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(pin: true)
        )
        return item
    }

    private func makePinMenuItem() -> NSMenuItem {
        let menuItem = NSMenuItem(
            title: String(localized: "Always on Top"),
            action: #selector(pinAction(_:)),
            keyEquivalent: ""
        )
        menuItem.target = self
        return menuItem
    }

    @objc private func pinAction(_ sender: Any?) {
        toggleAlwaysOnTop()
    }

    /// FR-007/FR-026: the pin is the single entry to always-on-top — host
    /// persists (immediate), the coordinator applies level + collection
    /// behavior (WindowLevelBridge is the behavioral authority).
    private func toggleAlwaysOnTop() {
        guard let host, var note = host.note else { return }
        note.alwaysOnTop.toggle()
        host.updateAppearance(note)
        coordinator?.updateAlwaysOnTop(noteId: noteId)
    }

    private func syncPinState(alwaysOnTop: Bool) {
        guard let item = items[NSToolbarItem.Identifier(NoteToolbarSpec.pinIdentifier)],
              let button = item.view as? NSButton else { return }
        button.state = alwaysOnTop ? .on : .off
        button.image = NSImage(
            systemSymbolName: alwaysOnTop ? "pin.fill" : "pin",
            accessibilityDescription: nil
        )
        button.toolTip = alwaysOnTop
            ? String(localized: "Always on Top: on")
            : String(localized: "Always on Top: off")
        button.setAccessibilityLabel(String(localized: "Always on Top"))
        button.setAccessibilityValue(alwaysOnTop ? String(localized: "On") : String(localized: "Off"))
        item.menuFormRepresentation?.state = alwaysOnTop ? .on : .off
        item.menuFormRepresentation?.target = self
        // FR-007: the toggle must not shift toolbar geometry — only state
        // and icon change.
    }

    // MARK: Appearance (004 T027, FR-008/FR-009)

    private func makeAppearanceItem() -> NSToolbarItem {
        let button = makeToolbarButton(systemImage: "paintpalette", action: #selector(appearanceAction(_:)))
        button.toolTip = String(localized: "Appearance")
        button.setAccessibilityLabel(String(localized: "Appearance"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.appearanceIdentifier,
            button: button,
            label: String(localized: "Appearance"),
            tooltip: String(localized: "Appearance"),
            menuForm: makeAppearanceSubmenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(pin: false)
        )
        return item
    }

    @objc private func appearanceAction(_ sender: NSButton) {
        showAppearancePanel(anchoredTo: sender)
    }

    /// NSPopover → NSHostingController → AppearancePanelView (non-activating
    /// anchor, standard behavior; FR-008 — immediate preview, no confirm).
    private func showAppearancePanel(anchoredTo view: NSView) {
        guard let host, let note = host.note else { return }
        if let appearancePopover {
            appearancePopover.close()
            self.appearancePopover = nil
        }
        let panel = AppearancePanelView(note: note) { [weak self] updated in
            guard let self else { return }
            host.updateAppearance(updated)
            self.coordinator?.updateNotePaper(noteId: self.noteId)
        }
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: panel)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 252, height: 330)
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        appearancePopover = popover
    }

    /// The appearance submenu (overflow form): colors 7 + opacity 13 steps
    /// + reset — migrated from the former NoteControlsView context menu
    /// (T027; single action source with the panel).
    private func makeAppearanceSubmenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Appearance"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: String(localized: "Appearance"))
        item.submenu = menu

        let colorMenu = NSMenu(title: String(localized: "Note Color"))
        let colorItem = NSMenuItem(title: String(localized: "Note Color"), action: nil, keyEquivalent: "")
        colorItem.submenu = colorMenu
        for key in NotePaletteKey.allCases {
            let actionItem = NSMenuItem(
                title: NotePalette.displayName(for: key),
                action: #selector(applyPaletteKey(_:)),
                keyEquivalent: ""
            )
            actionItem.target = self
            actionItem.representedObject = key.rawValue
            actionItem.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(
                NSImage.SymbolConfiguration(paletteColors: [NSColor(NotePalette.dynamicColor(for: key))])
            )
            if NotePalette.paletteKey(for: host?.note?.colorKey ?? .yellow) == key {
                actionItem.state = .on
            }
            colorMenu.addItem(actionItem)
        }
        menu.addItem(colorItem)

        let opacityMenu = NSMenu(title: String(localized: "Background Opacity"))
        let opacityItem = NSMenuItem(title: String(localized: "Background Opacity"), action: nil, keyEquivalent: "")
        opacityItem.submenu = opacityMenu
        for step in NoteAppearance.OpacityBounds.allSteps {
            let actionItem = NSMenuItem(
                title: NoteWindowDerivations.formatOpacityPercent(step),
                action: #selector(applyOpacityStep(_:)),
                keyEquivalent: ""
            )
            actionItem.target = self
            actionItem.representedObject = step
            if abs((host?.note?.transparency ?? 1.0) - step) < 0.001 {
                actionItem.state = .on
            }
            opacityMenu.addItem(actionItem)
        }
        menu.addItem(opacityItem)

        menu.addItem(NSMenuItem.separator())
        let resetItem = NSMenuItem(
            title: String(localized: "Restore Defaults"),
            action: #selector(applyDefaults(_:)),
            keyEquivalent: ""
        )
        resetItem.target = self
        menu.addItem(resetItem)
        return item
    }

    @objc private func applyPaletteKey(_ sender: NSMenuItem) {
        guard let host, let raw = sender.representedObject as? String,
              let key = NotePaletteKey(rawValue: raw) else { return }
        let updated = NoteWindowDerivations.note(applyingPaletteKey: key, to: host.note ?? .init(lastModifiedDeviceId: DeviceIdentity.current.id))
        host.updateAppearance(updated)
        coordinator?.updateNotePaper(noteId: noteId)
    }

    @objc private func applyOpacityStep(_ sender: NSMenuItem) {
        guard let host, let step = sender.representedObject as? Double else { return }
        var updated = host.note ?? .init(lastModifiedDeviceId: DeviceIdentity.current.id)
        updated.transparency = NoteWindowDerivations.clampedOpacity(step)
        host.updateAppearance(updated)
        coordinator?.updateNotePaper(noteId: noteId)
    }

    @objc private func applyDefaults(_ sender: NSMenuItem) {
        guard let host, let note = host.note else { return }
        let updated = NoteWindowDerivations.resetAppearance(of: note)
        host.updateAppearance(updated)
        coordinator?.updateNotePaper(noteId: noteId)
    }

    // MARK: Insert (004 T032, FR-010)

    private func makeInsertItem() -> NSToolbarItem {
        let button = makeToolbarButton(systemImage: "plus", action: #selector(insertAction(_:)))
        button.toolTip = String(localized: "Insert")
        button.setAccessibilityLabel(String(localized: "Insert"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.insertIdentifier,
            button: button,
            label: String(localized: "Insert"),
            tooltip: String(localized: "Insert"),
            menuForm: makeInsertMenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(pin: false)
        )
        return item
    }

    @objc private func insertAction(_ sender: NSButton) {
        // Pull-down button: show the same menu the overflow form uses.
        guard let menu = makeInsertMenu().submenu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    /// The unified Insert menu (FR-010/Q4): screenshot (region/window),
    /// file reference, image (new — T031), todo, code. Every action routes
    /// through the host's insertion methods with a resolved target
    /// (contracts §5) — no second insertion model.
    private func makeInsertMenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Insert"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: String(localized: "Insert"))
        item.submenu = menu

        let screenshotItem = NSMenuItem(
            title: String(localized: "Add Screenshot"),
            action: nil,
            keyEquivalent: ""
        )
        let screenshotMenu = NSMenu(title: String(localized: "Add Screenshot"))
        let regionItem = NSMenuItem(title: String(localized: "Capture Region…"), action: #selector(captureRegionAction(_:)), keyEquivalent: "")
        regionItem.target = self
        screenshotMenu.addItem(regionItem)
        let windowItem = NSMenuItem(title: String(localized: "Capture Window…"), action: #selector(captureWindowAction(_:)), keyEquivalent: "")
        windowItem.target = self
        screenshotMenu.addItem(windowItem)
        screenshotItem.submenu = screenshotMenu
        menu.addItem(screenshotItem)

        let fileItem = NSMenuItem(title: String(localized: "Insert File Reference…"), action: #selector(insertFileAction(_:)), keyEquivalent: "")
        fileItem.target = self
        menu.addItem(fileItem)

        let imageItem = NSMenuItem(title: String(localized: "Insert Image…"), action: #selector(insertImageAction(_:)), keyEquivalent: "")
        imageItem.target = self
        menu.addItem(imageItem)

        menu.addItem(NSMenuItem.separator())

        let todoItem = NSMenuItem(title: String(localized: "Add Todo"), action: #selector(insertTodoAction(_:)), keyEquivalent: "t")
        todoItem.keyEquivalentModifierMask = [.command, .shift]
        todoItem.target = self
        menu.addItem(todoItem)

        let codeItem = NSMenuItem(title: String(localized: "Add Code Block"), action: #selector(insertCodeAction(_:)), keyEquivalent: "c")
        codeItem.keyEquivalentModifierMask = [.command, .shift]
        codeItem.target = self
        menu.addItem(codeItem)
        return item
    }

    @objc private func captureRegionAction(_ sender: Any?) {
        guard let host else { return }
        let target = resolvedInsertionTarget()
        Task { await host.captureRegion(target: target) }
    }

    @objc private func captureWindowAction(_ sender: Any?) {
        guard let host else { return }
        let target = resolvedInsertionTarget()
        Task { await host.captureWindow(target: target) }
    }

    @objc private func insertFileAction(_ sender: Any?) {
        guard let host else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = resolvedInsertionTarget()
        Task { await host.insertFileReferenceBlock(url: url, target: target) }
    }

    @objc private func insertImageAction(_ sender: Any?) {
        guard let host else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = resolvedInsertionTarget()
        Task { await host.insertImageBlock(url: url, target: target) }
    }

    @objc private func insertTodoAction(_ sender: Any?) {
        guard let host else { return }
        let target = resolvedInsertionTarget()
        Task { await host.insertTodoBlock(target: target) }
    }

    @objc private func insertCodeAction(_ sender: Any?) {
        guard let host else { return }
        let target = resolvedInsertionTarget()
        Task { await host.insertCodeBlock(target: target) }
    }

    /// The insertion target snapshot taken at invocation (contracts §5):
    /// the caret/focus context of the note's editor, degraded to `.append`
    /// when stale.
    private func resolvedInsertionTarget() -> InsertionTarget {
        guard let host else { return .append }
        let context = EditorSelectionContext.current(for: host.noteId)
        return NoteWindowDerivations.resolveInsertionTarget(blocks: host.blocks, context: context)
    }

    // MARK: More (004 T022, FR-011)

    private func makeMoreItem() -> NSToolbarItem {
        let button = makeToolbarButton(systemImage: "ellipsis.circle", action: #selector(moreAction(_:)))
        button.toolTip = String(localized: "More")
        button.setAccessibilityLabel(String(localized: "More"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.moreIdentifier,
            button: button,
            label: String(localized: "More"),
            tooltip: String(localized: "More"),
            menuForm: makeMoreMenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(pin: false)
        )
        return item
    }

    @objc private func moreAction(_ sender: NSButton) {
        let menu = makeMoreMenu().submenu ?? NSMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    /// Low-frequency actions (FR-011): copy/export/trash + widget
    /// eligibility — migrated from the former NoteControlsView context menu
    /// (T022); the content-area context menu remains as a second
    /// presentation of the SAME actions (001 FR-031).
    private func makeMoreMenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "More"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: String(localized: "More"))
        item.submenu = menu

        let duplicate = NSMenuItem(title: String(localized: "Duplicate Note"), action: #selector(duplicateAction(_:)), keyEquivalent: "")
        duplicate.target = self
        menu.addItem(duplicate)

        let markdown = NSMenuItem(title: String(localized: "Copy as Markdown"), action: #selector(copyMarkdownAction(_:)), keyEquivalent: "")
        markdown.target = self
        menu.addItem(markdown)

        let export = NSMenuItem(title: String(localized: "Export as JSON…"), action: #selector(exportAction(_:)), keyEquivalent: "")
        export.target = self
        menu.addItem(export)

        let trash = NSMenuItem(title: String(localized: "Move to Trash"), action: #selector(trashAction(_:)), keyEquivalent: "\u{8}")
        trash.keyEquivalentModifierMask = [.command]
        trash.target = self
        menu.addItem(trash)

        menu.addItem(NSMenuItem.separator())

        // FR-112 (T280): widget eligibility (note-level).
        let widgetToggle = NSMenuItem(
            title: String(localized: "Allow in Widgets"),
            action: #selector(toggleWidgetEligibility(_:)),
            keyEquivalent: ""
        )
        widgetToggle.target = self
        widgetToggle.state = (host?.note?.widgetEligible ?? true) ? .on : .off
        menu.addItem(widgetToggle)

        // FR-110 (T306): the selected-note widget note.
        if WidgetNoteSelection.selectedNote() == noteId {
            let remove = NSMenuItem(title: String(localized: "Remove from Widget"), action: #selector(widgetNoteSelectionAction(_:)), keyEquivalent: "")
            remove.target = self
            menu.addItem(remove)
        } else {
            let set = NSMenuItem(title: String(localized: "Set as Widget Note"), action: #selector(widgetNoteSelectionAction(_:)), keyEquivalent: "")
            set.target = self
            menu.addItem(set)
        }
        return item
    }

    @objc private func duplicateAction(_ sender: Any?) {
        coordinator?.duplicateNote(noteId: noteId)
    }

    @objc private func copyMarkdownAction(_ sender: Any?) {
        coordinator?.copyNoteAsMarkdown(noteId: noteId)
    }

    @objc private func exportAction(_ sender: Any?) {
        coordinator?.exportNoteAsJSON(noteId: noteId)
    }

    @objc private func trashAction(_ sender: Any?) {
        coordinator?.moveToTrash(noteId: noteId)
    }

    @objc private func toggleWidgetEligibility(_ sender: NSMenuItem) {
        guard let host, var note = host.note else { return }
        note.widgetEligible.toggle()
        host.updateAppearance(note)
    }

    @objc private func widgetNoteSelectionAction(_ sender: NSMenuItem) {
        if WidgetNoteSelection.selectedNote() == noteId {
            WidgetNoteSelection.setSelectedNote(nil)
        } else {
            WidgetNoteSelection.setSelectedNote(noteId)
        }
    }
}

// MARK: - Localized palette names (shared with the appearance panel)

extension NotePalette {
    /// The localized display name for a palette key (001 FR-180a).
    static func displayName(for key: NotePaletteKey) -> String {
        switch key {
        case .yellow:   return String(localized: "Yellow")
        case .peach:    return String(localized: "Peach")
        case .pink:     return String(localized: "Pink")
        case .green:    return String(localized: "Green")
        case .blue:     return String(localized: "Blue")
        case .lavender: return String(localized: "Lavender")
        case .gray:     return String(localized: "Gray")
        }
    }
}
