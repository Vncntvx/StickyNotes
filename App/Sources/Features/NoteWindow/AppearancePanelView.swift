import SwiftUI
import Domain

// MARK: - AppearancePanelView (004 T026, FR-008/FR-009)
//
// Per plan.md §4.2 and contracts §3: the appearance popover content —
// seven-key palette (with custom preserved byte-exact per 001 FR-032),
// opacity slider (0.40–1.00 / 0.05, full "NN%" value at ANY width), and a
// Restore Defaults button (default palette color + 1.0). Every change
// calls `onAppearanceChange` immediately (FR-008 instant preview — no
// confirm button); nothing is persisted here (FR-015c: the popover is
// session-only state).

struct AppearancePanelView: View {
    let note: Note
    let onAppearanceChange: (Note) -> Void

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
                onAppearanceChange(NoteWindowDerivations.resetAppearance(of: note))
            }
            .font(.body)
        }
        .padding(16)
        .frame(width: 252)
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
        let selected = NoteWindowDerivations.paletteKey(for: note) == key
        return Button {
            onAppearanceChange(NoteWindowDerivations.note(applyingPaletteKey: key, to: note))
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
        HStack(spacing: 10) {
            Slider(
                value: Binding(
                    get: { NoteWindowDerivations.clampedOpacity(note.transparency) },
                    set: { newValue in
                        var updated = note
                        updated.transparency = NoteWindowDerivations.clampedOpacity(newValue)
                        onAppearanceChange(updated)
                    }
                ),
                in: 0.40...1.00,
                step: 0.05
            )
            .accessibilityLabel(String(localized: "Background Opacity"))
            .accessibilityValue(NoteWindowDerivations.formatOpacityPercent(note.transparency))
            .help(String(localized: "Background Opacity"))

            // FR-009: complete "NN%" — fixed-width slot so the value never
            // truncates at any panel width.
            Text(NoteWindowDerivations.formatOpacityPercent(note.transparency))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}
