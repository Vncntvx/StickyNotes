import SwiftUI
import Domain

// MARK: - AppearancePanelView (004 T026, FR-008/FR-009)
//
// Per plan.md §4.2 and contracts §3: the appearance popover content —
// seven-key palette (with custom preserved byte-exact per 001 FR-032),
// opacity slider (0.00–1.00 / 0.05 — 004 Q8, full "NN%" value at ANY
// width), and a Restore Defaults button (default palette color + 1.0). Every change
// calls `onAppearanceChange` immediately (FR-008 instant preview — no
// confirm button); nothing is persisted here (FR-015c: the popover is
// session-only state).

struct AppearancePanelView: View {
    let note: Note
    let onAppearanceChange: (Note) -> Void

    // 004 T069 (2026-08-13): LOCAL reactive state — the panel follows its
    // own edits live (slider knob follows the mouse, "NN%" updates while
    // dragging, palette checkmark moves on click). The base `note` stays
    // the ORIGINAL snapshot; every change composes base + current local
    // state (non-appearance fields survive the composition).
    @State private var transparency: Double
    @State private var colorKey: NoteColorKey
    @State private var customColor: String?

    init(note: Note, onAppearanceChange: @escaping (Note) -> Void) {
        self.note = note
        self.onAppearanceChange = onAppearanceChange
        _transparency = State(initialValue: NoteWindowDerivations.clampedOpacity(note.transparency))
        _colorKey = State(initialValue: note.colorKey)
        _customColor = State(initialValue: note.customColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(String(localized: "Appearance"))
                .font(.headline)

            // MARK: Color palette (7 keys + custom; FR-032 verbatim)
            Text(String(localized: "Note Color"))
                .font(.caption)
                .foregroundStyle(.secondary)
            paletteGrid

            // MARK: Opacity (FR-008/FR-009 — full value, never truncated)
            Text(String(localized: "Background Opacity"))
                .font(.caption)
                .foregroundStyle(.secondary)
            opacityRow

            Divider()

            Button(String(localized: "Restore Defaults")) {
                let updated = NoteWindowDerivations.resetAppearance(of: note)
                colorKey = updated.colorKey
                customColor = updated.customColor
                transparency = 1.0
                onAppearanceChange(updated)
            }
            .font(.body)
        }
        .padding(16)
        .frame(width: 252)
        // 004 T072 (2026-08-13): SOLID material surface — the panel is a
        // borderless child window with a clear background; without this
        // the note shows through the panel (user report: "面板也变成透明
        // 了，面板不应该更改"). The system material is opaque regardless
        // of the note's transparency.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// The composed note reflecting the CURRENT local appearance state
    /// over the original snapshot (004 T069).
    private var currentNote: Note {
        NoteWindowDerivations.composeAppearance(
            base: note,
            colorKey: colorKey,
            customColor: customColor,
            transparency: transparency
        )
    }

    // MARK: - Palette

    private var paletteKeys: [NotePaletteKey] {
        NotePaletteKey.allCases
    }

    private var paletteGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 7), spacing: 10) {
            ForEach(paletteKeys, id: \.self) { key in
                paletteButton(key)
            }
        }
    }

    private func paletteButton(_ key: NotePaletteKey) -> some View {
        let selected = NoteWindowDerivations.paletteKey(for: currentNote) == key
        return Button {
            var base = note
            base.transparency = transparency
            base.customColor = customColor
            let updated = NoteWindowDerivations.note(applyingPaletteKey: key, to: base)
            colorKey = updated.colorKey
            customColor = updated.customColor
            onAppearanceChange(updated)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(NotePalette.dynamicColor(for: key))
                        .frame(width: 24, height: 24)
                        .overlay {
                            Circle()
                                .strokeBorder(.primary.opacity(0.15), lineWidth: 1)
                        }
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotePalette.dynamicForeground(for: key))
                    }
                }
                // 001 FR-044: selection is conveyed by checkmark + name +
                // swatch — never color alone.
                Text(NotePalette.displayName(for: key))
                    .font(.system(size: 9))
                    .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .help(NotePalette.displayName(for: key))
        .accessibilityLabel(NotePalette.displayName(for: key))
        .accessibilityValue(selected ? String(localized: "Selected") : "")
    }

    // MARK: - Opacity

    private var opacityRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Slider(
                    value: Binding(
                        get: { transparency },
                        set: { newValue in
                            let stepped = NoteWindowDerivations.clampedOpacity(newValue)
                            transparency = stepped
                            onAppearanceChange(NoteWindowDerivations.composeAppearance(
                                base: note,
                                colorKey: colorKey,
                                customColor: customColor,
                                transparency: stepped
                            ))
                        }
                    ),
                    in: NoteAppearance.OpacityBounds.minOpacity...NoteAppearance.OpacityBounds.maxOpacity,
                    step: NoteAppearance.OpacityBounds.step
                )
                .accessibilityLabel(String(localized: "Background Opacity"))
                .accessibilityValue(NoteWindowDerivations.formatOpacityPercent(transparency))
                .help(String(localized: "Background Opacity"))

                // FR-009: complete "NN%" — fixed-width slot so the value never
                // truncates at any panel width.
                Text(NoteWindowDerivations.formatOpacityPercent(transparency))
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 44, alignment: .trailing)
                    .accessibilityHidden(true)
            }
            // 004 Q8 (2026-08-13): visible range endpoints — the range is
            // 0%–100% (FR-008 / 001 FR-041a per Q8), matching the overflow
            // menu's 21 steps and the ⌥O stepping path.
            HStack {
                Text(NoteWindowDerivations.formatOpacityPercent(NoteAppearance.OpacityBounds.minOpacity))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(NoteWindowDerivations.formatOpacityPercent(NoteAppearance.OpacityBounds.maxOpacity))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
