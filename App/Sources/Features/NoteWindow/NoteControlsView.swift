import SwiftUI
import Domain

// MARK: - NoteControlsView (T165/T234/T257/T248/T301)
//
// Per tasks.md T165/T234/T257/T248/T301 and spec FR-030/FR-030a/FR-031/
// FR-032/FR-033/FR-034/FR-035/FR-042/FR-043a/FR-044: the upper control area —
// title, color, transparency (opacity 40–100% in 5-pt steps, FR-041a),
// text size (9–24 pt in 1-pt steps, FR-043a), Always-on-Top (FR-036),
// screenshot / file-ref / actions / close — hidden until the pointer enters
// (FR-031; keyboard alternatives per FR-181). The note's contextual menu
// (FR-031) hosts duplicate/copy-as-Markdown/export/move-to-Trash (T248) and
// the widget-eligibility toggle (FR-112, T280). T301: the appearance
// controls are keyboard-reachable without hover — ⌥C/⌥O/⌥T stepping
// shortcuts plus full-value "Appearance" submenus in the contextual menu.

/// The upper control area of a note window (hidden until pointer enter).
public struct NoteControlsView: View {
    let note: Note
    let onChanged: (Note) -> Void
    /// FR-031 note-level actions (T282). Wired by the note-window host:
    /// duplicate / copy-as-Markdown / export-JSON / move-to-Trash.
    let onDuplicate: () -> Void
    let onCopyAsMarkdown: () -> Void
    let onExport: () -> Void
    let onMoveToTrash: () -> Void
    /// FR-031 upper-area media entries (T290/T293): add a screenshot /
    /// add a file reference.
    let onAddScreenshot: () -> Void
    let onAddFileReference: () -> Void

    // 003 T033 / user decision 2026-08-09: the controls row is ALWAYS
    // visible — the FR-031 hover-reveal (isVisible) and the FR-045
    // active-only emphasis gating were removed. (Spec/FR sync pending.)

    public init(
        note: Note,
        onChanged: @escaping (Note) -> Void,
        onAddScreenshot: @escaping () -> Void = {},
        onAddFileReference: @escaping () -> Void = {},
        onDuplicate: @escaping () -> Void = {},
        onCopyAsMarkdown: @escaping () -> Void = {},
        onExport: @escaping () -> Void = {},
        onMoveToTrash: @escaping () -> Void = {}
    ) {
        self.note = note
        self.onChanged = onChanged
        self.onAddScreenshot = onAddScreenshot
        self.onAddFileReference = onAddFileReference
        self.onDuplicate = onDuplicate
        self.onCopyAsMarkdown = onCopyAsMarkdown
        self.onExport = onExport
        self.onMoveToTrash = onMoveToTrash
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Adaptive controls row (user decision 2026-08-09): ONE
            // ViewThatFits whose variants are COMPLETE rows — the title
            // lives INSIDE each variant, so there is no layout competition
            // between a flexible title and fixed controls (that earlier
            // split produced greedy-title thresholds and clipped rows).
            // Each variant is measured against the real row width and the
            // first that fits wins: full → core → essential. The hidden
            // controls stay reachable via the Appearance submenus (T301,
            // ⌥C/⌥O/⌥T), Edit/Insert menu commands (T032) and the context
            // menu — no feature loss. The title is content-sized (up to
            // 160pt): a short title never wastes window width, so the full
            // row appears at a normal note-window width.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    titleField
                    colorPicker
                    opacityPicker
                    textSizePicker
                    alwaysOnTopToggle
                    cameraButton
                    paperclipButton
                    closeButton
                }
                HStack(spacing: 8) {
                    titleField
                    colorPicker
                    opacityPicker
                    alwaysOnTopToggle
                    closeButton
                }
                HStack(spacing: 8) {
                    titleField
                    colorPicker
                    alwaysOnTopToggle
                    closeButton
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .contextMenu {
            // FR-031 contextual menu (T248): duplicate + copy-as-Markdown.
            Button("Duplicate Note") { onDuplicate() }
            Button("Copy as Markdown") { onCopyAsMarkdown() }
            Divider()
            Button("Export as JSON…") { onExport() }
            Button("Move to Trash") { onMoveToTrash() }
            Divider()
            // T301 (FR-181): full-value appearance submenus — every color /
            // opacity step / text size is reachable without pointer hover.
            Menu("Appearance") {
                Menu("Note Color") {
                    ForEach(NotePaletteKey.allCases, id: \.self) { key in
                        Button {
                            applyPalette(key)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(paletteColor(for: key))
                                    .frame(width: 10, height: 10)
                                Text(paletteDisplayName(for: key))
                            }
                        }
                    }
                }
                Menu("Background Opacity") {
                    ForEach(NoteAppearance.OpacityBounds.allSteps, id: \.self) { step in
                        Button("\(Int(step * 100))%") {
                            var updated = note
                            updated.transparency = step
                            onChanged(updated)
                        }
                    }
                }
                Menu("Text Size") {
                    ForEach(NoteAppearance.TextSizeBounds.allSizes, id: \.self) { size in
                        Button("\(size) pt") {
                            var updated = note
                            updated.textSize = size
                            onChanged(updated)
                        }
                    }
                }
            }
            Divider()
            // FR-112 (T280): widget-eligibility toggle lives HERE (note
            // level), NOT on the control bar.
            Toggle(isOn: Binding(
                get: { note.widgetEligible },
                set: { newValue in
                    var updated = note
                    updated.widgetEligible = newValue
                    onChanged(updated)
                }
            )) {
                Text("Allow in Widgets")
            }
            Divider()
            // FR-110 (T306): pick the note shown by the selected-note
            // widget forms (small-selected / medium-todo). Note-level like
            // the other FR-031 actions; keyboard-accessible via the menu.
            if WidgetNoteSelection.selectedNote() == note.id {
                Button("Remove from Widget") {
                    WidgetNoteSelection.setSelectedNote(nil)
                }
            } else {
                Button("Set as Widget Note") {
                    WidgetNoteSelection.setSelectedNote(note.id)
                }
            }
        }
        // T301 (FR-181): keyboard alternatives for the hover-only controls —
        // ⌥C (next color), ⌥O (next opacity step), ⌥T (next text size). The
        // buttons stay in the hierarchy (`.hidden()`) so the shortcuts are
        // registered even while the hover bar is collapsed.
        .overlay(alignment: .topLeading) {
            HStack(spacing: 0) {
                Button("") { cycleNextColor() }
                    .keyboardShortcut("c", modifiers: .option)
                Button("") { cycleNextOpacity() }
                    .keyboardShortcut("o", modifiers: .option)
                Button("") { cycleNextTextSize() }
                    .keyboardShortcut("t", modifiers: .option)
            }
            .hidden()
            .accessibilityHidden(true)
        }
    }

    // MARK: - Controls (FR-031/FR-041a/FR-043a)

    private var colorPicker: some View {
        Menu {
            // 003 T037 (FR-030): the seven-color palette with per-appearance
            // design values; old color keys map semantically (紫→薰衣草,
            // FR-032). Custom colors are preserved (001 FR-040).
            ForEach(NotePaletteKey.allCases, id: \.self) { key in
                Button {
                    applyPalette(key)
                } label: {
                    HStack {
                        Circle()
                            .fill(paletteColor(for: key))
                            .frame(width: 10, height: 10)
                        Text(paletteDisplayName(for: key))
                    }
                }
            }
        } label: {
            Image(systemName: "paintpalette")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Note color")
        .accessibilityLabel("Note color")
    }

    private var opacityPicker: some View {
        Picker("Opacity", selection: Binding(
            get: { NoteAppearance.OpacityBounds.clamped(note.transparency) },
            set: { newValue in
                var updated = note
                updated.transparency = newValue
                onChanged(updated)
            }
        )) {
            ForEach(NoteAppearance.OpacityBounds.allSteps, id: \.self) { step in
                Text("\(Int(step * 100))%").tag(step)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: 62, maxWidth: 90)
        .help("Background opacity")
        .accessibilityLabel("Background opacity")
    }

    private var textSizePicker: some View {
        Picker("Text Size", selection: Binding(
            get: { NoteAppearance.TextSizeBounds.clamped(note.textSize) },
            set: { newValue in
                var updated = note
                updated.textSize = newValue
                onChanged(updated)
            }
        )) {
            ForEach(NoteAppearance.TextSizeBounds.allSizes, id: \.self) { size in
                Text("\(size) pt").tag(size)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(minWidth: 52, maxWidth: 80)
        .help("Text size")
        .accessibilityLabel("Text size")
    }

    // MARK: - Adaptive row

    /// The title field (FR-031): content-sized up to 160pt so a short
    /// title never wastes window width (the controls get the room instead
    /// — verified 2026-08-09). Truncates with an ellipsis when squeezed.
    private var titleField: some View {
        TextField("Title", text: Binding(
            get: { note.title ?? "" },
            set: { newValue in
                var updated = note
                updated.title = newValue.isEmpty ? nil : newValue
                onChanged(updated)
            }
        ))
        .textFieldStyle(.plain)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 160, alignment: .leading)
    }

    /// FR-031 (T293): add a screenshot.
    private var cameraButton: some View {
        Button {
            onAddScreenshot()
        } label: {
            Image(systemName: "camera")
        }
        .buttonStyle(.plain)
        .help("Add screenshot")
        .accessibilityLabel("Add screenshot")
    }

    /// FR-031 (T293): add a file reference.
    private var paperclipButton: some View {
        Button {
            onAddFileReference()
        } label: {
            Image(systemName: "paperclip")
        }
        .buttonStyle(.plain)
        .help("Add file reference")
        .accessibilityLabel("Add file reference")
    }

    /// Close — mirrors the traffic-light close (always available).
    private var closeButton: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .keyboardShortcut("w", modifiers: .command)
        .help("Close note")
        .accessibilityLabel("Close note")
    }

    private var alwaysOnTopToggle: some View {
        Button {
            var updated = note
            updated.alwaysOnTop.toggle()
            onChanged(updated)
        } label: {
            Image(systemName: note.alwaysOnTop ? "pin.fill" : "pin")
        }
        .buttonStyle(.plain)
        .help(note.alwaysOnTop ? "Always on top: on" : "Always on top: off")
        .accessibilityLabel("Always on top")
        .accessibilityValue(note.alwaysOnTop ? "On" : "Off")
    }

    // MARK: - Close (handled by the hosting NSWindow)

    private func onClose() {
        // The window close is handled by the hosting NSWindow.
        NSApp.keyWindow?.close()
    }

    // MARK: - 003 T037 palette helpers (FR-030/FR-032)

    /// The palette's per-appearance dynamic color (FR-030 design values).
    private func paletteColor(for key: NotePaletteKey) -> Color {
        NotePalette.dynamicColor(for: key)
    }

    /// The stored representation of a palette selection (FR-032):
    /// - colors with a Domain equivalent map to that stored key
    ///   (lavender → purple; renders via the palette on read-back);
    /// - peach has NO Domain built-in (StickyCore zero-change) — it is
    ///   preserved as a custom color with the palette's designed light
    ///   value (custom colors are preserved byte-exact per FR-032).
    private struct PaletteStorage {
        let colorKey: NoteColorKey
        let customColorHex: String?
    }

    private func paletteStorage(for key: NotePaletteKey) -> PaletteStorage {
        switch key {
        case .yellow:   return PaletteStorage(colorKey: .yellow, customColorHex: nil)
        case .peach:    return PaletteStorage(colorKey: .custom, customColorHex: "#FFC9A8")
        case .pink:     return PaletteStorage(colorKey: .pink, customColorHex: nil)
        case .green:    return PaletteStorage(colorKey: .green, customColorHex: nil)
        case .blue:     return PaletteStorage(colorKey: .blue, customColorHex: nil)
        case .lavender: return PaletteStorage(colorKey: .purple, customColorHex: nil)
        case .gray:     return PaletteStorage(colorKey: .gray, customColorHex: nil)
        }
    }

    /// The localized palette display name.
    private func paletteDisplayName(for key: NotePaletteKey) -> String {
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

    /// Applies a palette selection to the note (storage via FR-032 map).
    private func applyPalette(_ key: NotePaletteKey) {
        var updated = note
        let storage = paletteStorage(for: key)
        updated.colorKey = storage.colorKey
        updated.customColor = storage.customColorHex
        onChanged(updated)
    }

    private func colorFor(_ key: NoteColorKey) -> Color {
        guard let rgb = key.builtinRGB else { return .gray }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - T301 keyboard alternatives (FR-181)

    /// ⌥C: steps to the next palette color (wraps).
    private func cycleNextColor() {
        let colors = NotePaletteKey.allCases
        // Find the current palette key from the note's stored key.
        let currentKey = NotePalette.paletteKey(for: note.colorKey) ?? .yellow
        guard let current = colors.firstIndex(of: currentKey) else {
            applyPalette(colors[0])
            return
        }
        applyPalette(colors[(current + 1) % colors.count])
    }

    /// ⌥O: steps to the next opacity step (wraps).
    private func cycleNextOpacity() {
        let steps = NoteAppearance.OpacityBounds.allSteps
        guard let current = steps.firstIndex(of: note.transparency) else {
            applyOpacity(steps[0])
            return
        }
        applyOpacity(steps[(current + 1) % steps.count])
    }

    private func applyOpacity(_ step: Double) {
        var updated = note
        updated.transparency = step
        onChanged(updated)
    }

    /// ⌥T: steps to the next text size (wraps).
    private func cycleNextTextSize() {
        let sizes = NoteAppearance.TextSizeBounds.allSizes
        guard let current = sizes.firstIndex(of: note.textSize) else {
            applyTextSize(sizes[0])
            return
        }
        applyTextSize(sizes[(current + 1) % sizes.count])
    }

    private func applyTextSize(_ size: Int) {
        var updated = note
        updated.textSize = size
        onChanged(updated)
    }
}

extension NoteColorKey {
    /// Language-neutral display name for the built-in colors (the App
    /// layer localizes in catalogs).
    var displayName: String {
        rawValue.capitalized
    }
}
