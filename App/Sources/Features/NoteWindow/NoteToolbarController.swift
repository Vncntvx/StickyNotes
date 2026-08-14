import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Domain
import SystemBridge

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
    /// The appearance panel (004 T071: a manually-placed borderless CHILD
    /// window — NSPopover anchoring is unreliable for Liquid Glass windows
    /// on macOS 27; see `showAppearancePanel`). Closed on teardown;
    /// FR-015c — no persistence of open state.
    private var appearancePanel: NSWindow?
    /// Dismissal monitor for the appearance panel (click-outside / ESC).
    private var appearancePanelMonitor: Any?
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
        // 004 T064: medium density (small size mode) — see NoteToolbarSpec.
        toolbar.sizeMode = NoteToolbarSpec.toolbarSizeMode
        // Item sets come from the delegate methods
        // (`toolbarDefaultItemIdentifiers:`/`toolbarAllowedItemIdentifiers:`).
        startObserving()
    }

    deinit {
        isTearingDown = true
        MainActor.assumeIsolated {
            removeAppearancePanelDismissalMonitor()
        }
    }

    /// Closes transient UI and stops observation (called on the same
    /// release path as the window delegate — contracts §1).
    func teardown() {
        isTearingDown = true
        closeAppearancePanel()
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
        // 004 T069 (2026-08-13): the appearance submenu (overflow form)
        // mirrors the CURRENT appearance — rebuilt on change so its
        // color/opacity checkmarks never go stale vs the panel/note.
        if let appearanceItem = items[NSToolbarItem.Identifier(NoteToolbarSpec.appearanceIdentifier)] {
            appearanceItem.menuFormRepresentation = makeAppearanceSubmenu()
        }
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

    /// A standard toolbar button view (004 T067, 2026-08-13): borderless
    /// at rest — the button has NO capsule boundary of its own; the system
    /// shows a local glass response only on hover/press/keyboard focus.
    /// Liquid Glass stays as the toolbar's overall surface (FR-021/FR-022:
    /// system-provided; no hand-drawn chrome).
    private func makeToolbarButton(systemImage: String, pointSize: CGFloat, action: Selector) -> NSButton {
        let button = NSButton()
        button.bezelStyle = NoteToolbarSpec.buttonBezelStyle
        // 004 T064: small control size (medium density — see NoteToolbarSpec).
        button.controlSize = NoteToolbarSpec.buttonControlSize
        button.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
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
        let button = makeToolbarButton(
            systemImage: NoteToolbarSpec.pinSymbolName,
            pointSize: NoteToolbarSpec.symbolPointSize,
            action: #selector(pinAction(_:))
        )
        // 004 T067 (2026-08-13): the pinned state is expressed by the
        // SYMBOL (pin ↔ pin.fill), not by a dark tinted button surface —
        // momentary push-in keeps no persistent highlight; the
        // accessibility value + menu checkmark carry the state.
        let item = toolbarItem(
            identifier: NoteToolbarSpec.pinIdentifier,
            button: button,
            label: String(localized: "Always on Top"),
            tooltip: String(localized: "Always on Top"),
            menuForm: makePinMenuItem(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(itemIdentifier: NoteToolbarSpec.pinIdentifier)
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
        // 004 T067: symbol-only state — no `button.state` toggle highlight.
        button.image = NSImage(
            systemSymbolName: alwaysOnTop
                ? NoteToolbarSpec.pinSymbolName + ".fill"
                : NoteToolbarSpec.pinSymbolName,
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: NoteToolbarSpec.symbolPointSize, weight: .regular)
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
        let button = makeToolbarButton(
            systemImage: NoteToolbarSpec.appearanceSymbolName,
            pointSize: NoteToolbarSpec.paletteSymbolPointSize,
            action: #selector(appearanceAction(_:))
        )
        button.toolTip = String(localized: "Note Appearance")
        button.setAccessibilityLabel(String(localized: "Note Appearance"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.appearanceIdentifier,
            button: button,
            label: String(localized: "Note Appearance"),
            tooltip: String(localized: "Note Appearance"),
            menuForm: makeAppearanceSubmenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(itemIdentifier: NoteToolbarSpec.appearanceIdentifier)
        )
        return item
    }

    @objc private func appearanceAction(_ sender: NSButton) {
        showAppearancePanel(anchoredTo: sender)
    }

    /// 004 T071 (2026-08-13): a borderless CHILD window hosts the panel —
    /// NSPopover anchoring proved unreliable for Liquid Glass windows on
    /// macOS 27 (every conversion-based variant landed the popover at the
    /// top of the screen; the shell windows misreport coordinates). A
    /// child window placed from the note window's screen FRAME is
    /// deterministic: it tracks the parent on move/resize, closes with it,
    /// and dismisses on click-outside / ESC via a local event monitor.
    private func showAppearancePanel(anchoredTo view: NSView) {
        guard let host, let note = host.note else { return }
        closeAppearancePanel()
        let panelView = AppearancePanelView(note: note) { [weak self] updated in
            guard let self else { return }
            host.updateAppearance(updated)
            self.coordinator?.updateNotePaper(noteId: self.noteId)
        }
        guard let noteWindow = NoteWindowBridge.registeredWindow(for: noteId) else { return }
        let hosting = NSHostingController(rootView: panelView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 252, height: 360),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        let panelSize = hosting.view.fittingSize
        // Screen-coordinate placement (window-management space — the only
        // reliable space on the Liquid Glass shell): leading edge near the
        // palette button, top edge just below the toolbar band.
        let frame = noteWindow.frame
        let panelFrame = NSRect(
            x: frame.minX + NoteToolbarSpec.panelLeadingInset,
            y: frame.maxY - NoteToolbarSpec.panelTopInset - panelSize.height,
            width: panelSize.width,
            height: panelSize.height
        )
        panel.setFrame(panelFrame, display: false)
        noteWindow.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        installAppearancePanelDismissalMonitor(panel: panel)
        appearancePanel = panel
    }

    private func closeAppearancePanel() {
        removeAppearancePanelDismissalMonitor()
        if let appearancePanel {
            if let parent = appearancePanel.parent {
                parent.removeChildWindow(appearancePanel)
            }
            appearancePanel.close()
        }
        appearancePanel = nil
    }

    private func installAppearancePanelDismissalMonitor(panel: NSWindow) {
        removeAppearancePanelDismissalMonitor()
        appearancePanelMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self, weak panel] event in
            guard let self, let panel, self.appearancePanel === panel else { return event }
            switch event.type {
            case .leftMouseDown, .rightMouseDown:
                if event.window !== panel {
                    self.closeAppearancePanel()
                }
            case .keyDown where event.keyCode == 53:  // ESC
                self.closeAppearancePanel()
            default:
                break
            }
            return event
        }
    }

    private func removeAppearancePanelDismissalMonitor() {
        if let appearancePanelMonitor {
            NSEvent.removeMonitor(appearancePanelMonitor)
        }
        appearancePanelMonitor = nil
    }

    /// The appearance submenu (overflow form): colors 7 + opacity 21 steps
    /// (0–100%, 004 Q8) + reset — migrated from the former NoteControlsView
    /// context menu (T027; single action source with the panel).
    private func makeAppearanceSubmenu() -> NSMenuItem {
        let item = NSMenuItem(title: String(localized: "Note Appearance"), action: nil, keyEquivalent: "")
        let menu = NSMenu(title: String(localized: "Note Appearance"))
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
        let button = makeToolbarButton(
            systemImage: NoteToolbarSpec.insertSymbolName,
            pointSize: NoteToolbarSpec.symbolPointSize,
            action: #selector(insertAction(_:))
        )
        button.toolTip = String(localized: "Insert")
        button.setAccessibilityLabel(String(localized: "Insert"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.insertIdentifier,
            button: button,
            label: String(localized: "Insert"),
            tooltip: String(localized: "Insert"),
            menuForm: makeInsertMenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(itemIdentifier: NoteToolbarSpec.insertIdentifier)
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

        let codeItem = NSMenuItem(title: String(localized: "Add Block"), action: #selector(insertCodeAction(_:)), keyEquivalent: "c")
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
        let button = makeToolbarButton(
            systemImage: NoteToolbarSpec.moreSymbolName,
            pointSize: NoteToolbarSpec.symbolPointSize,
            action: #selector(moreAction(_:))
        )
        button.toolTip = String(localized: "More")
        button.setAccessibilityLabel(String(localized: "More"))
        let item = toolbarItem(
            identifier: NoteToolbarSpec.moreIdentifier,
            button: button,
            label: String(localized: "More"),
            tooltip: String(localized: "More"),
            menuForm: makeMoreMenu(),
            priority: NoteWindowDerivations.toolbarVisibilityPriority(itemIdentifier: NoteToolbarSpec.moreIdentifier)
        )
        return item
    }

    @objc private func moreAction(_ sender: NSButton) {
        let menu = makeMoreMenu().submenu ?? NSMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 2), in: sender)
    }

    /// Low-frequency actions (FR-011): copy/export/trash — migrated from the
    /// former NoteControlsView context menu (T022); the content-area context
    /// menu remains as a second presentation of the SAME actions (001
    /// FR-031). (Widget menu items were removed 2026-08-13 with the widget
    /// surface.)
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
