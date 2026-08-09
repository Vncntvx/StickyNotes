import SwiftUI
import Domain

// MARK: - NoteCardView (003 T022, FR-020/FR-023/FR-025/SC-022)
//
// Per tasks.md T022 and spec FR-020/FR-023/FR-025/SC-022:
// - Density: card height 72–128 pt (NoteCardMetrics bounds), no large
//   blank areas; information priority title/first line → 2-line preview →
//   modified time (FR-020).
// - Selection state clear but not dominant and NOT color-only (FR-023):
//   keyboard selection adds a visible ring + the readable-foreground
//   accent; hover context actions never change card size (FR-023/CHK036).
// - FR-025 fields preserved: 2-line preview truncation, relative/absolute
//   time boundary, todo progress, cover thumbnail, conflict/sync badges —
//   CardProjection semantics and 001 rules unchanged (layout only).
// - Background from the palette (FR-022/FR-030 per-appearance design);
//   foreground via ReadableTheme (FR-033).

/// The card-grid note card.
public struct NoteCardView: View {
    let card: LibraryModel.NoteCardRow
    let isKeyboardSelected: Bool
    let action: () -> Void

    /// SC-022 density bounds (003 T014 asserts the view uses these).
    public static let contentHeightBounds = NoteCardMetrics.minCardHeight...NoteCardMetrics.maxCardHeight

    public init(
        card: LibraryModel.NoteCardRow,
        isKeyboardSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.card = card
        self.isKeyboardSelected = isKeyboardSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    titleText
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if card.syncWarning {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Sync warning")
                    }
                    if card.isConflictCopy {
                        Image(systemName: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Conflict copy")
                    }
                }

                // FR-020a: 2-line preview with trailing ellipsis; drawn from
                // the first rich-text block, never the summary title.
                if let preview = card.previewSource {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(secondaryText)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let progress = card.todoProgress {
                        Label(progress, systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(secondaryText)
                    }
                    if card.hasScreenshot {
                        Image(systemName: "camera")
                            .font(.caption2)
                            .foregroundStyle(secondaryText)
                            .accessibilityLabel("Has screenshot")
                    }
                    if card.hasImage {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(secondaryText)
                            .accessibilityLabel("Has image")
                    }
                    if card.hasFileReference {
                        Image(systemName: "doc")
                            .font(.caption2)
                            .foregroundStyle(secondaryText)
                            .accessibilityLabel("Has file reference")
                    }
                    Spacer(minLength: 0)
                    Text(DisplayFormatters.lastModified(card.modifiedAt))
                        .font(.caption2)
                        .foregroundStyle(secondaryText)
                }
            }
            .padding(10)
            // SC-022 (003 T022): content-driven height within 72–128.
            .frame(
                maxWidth: .infinity,
                minHeight: NoteCardMetrics.minCardHeight,
                maxHeight: NoteCardMetrics.maxCardHeight,
                alignment: .leading
            )
            .background(cardColor, in: RoundedRectangle(cornerRadius: AppMetrics.surfaceRadius))
            .overlay {
                // FR-023: keyboard selection is a clear-but-restrained ring
                // PLUS the foreground accent — never color-only.
                if isKeyboardSelected {
                    RoundedRectangle(cornerRadius: AppMetrics.surfaceRadius)
                        .strokeBorder(primaryText, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isKeyboardSelected ? [.isSelected] : [])
    }

    private var titleText: Text {
        if let title = card.title, !title.isEmpty {
            return Text(title).font(.headline).foregroundStyle(primaryText)
        }
        if let summary = card.summary {
            return Text(summary).font(.headline).foregroundStyle(primaryText)
        }
        return Text("Untitled note").font(.headline).foregroundStyle(secondaryText)
    }

    private var cardColor: Color {
        // FR-022/FR-030 (003 T022): built-in colors resolve through the
        // palette (per-appearance design); custom colors keep the Domain
        // projection (001 FR-040a) — the raw hex travels on the row
        // (verified 2026-08-09: peach — a custom-stored palette color —
        // rendered white without it).
        if let paletteKey = NotePalette.paletteKey(for: card.colorKey) {
            return NotePalette.dynamicColor(for: paletteKey)
        }
        if let customHex = card.customColorHex, let parsed = RGBColor(hex: customHex) {
            return Color(red: parsed.red, green: parsed.green, blue: parsed.blue, opacity: 1.0)
        }
        if let builtin = card.colorKey.builtinRGB {
            return Color(red: builtin.red, green: builtin.green, blue: builtin.blue, opacity: 1.0)
        }
        return Color(nsColor: .textBackgroundColor)
    }

    private var primaryText: Color {
        if let paletteKey = NotePalette.paletteKey(for: card.colorKey) {
            return NotePalette.dynamicForeground(for: paletteKey)
        }
        return .primary
    }

    private var secondaryText: Color {
        if let paletteKey = NotePalette.paletteKey(for: card.colorKey) {
            return NotePalette.dynamicSecondaryForeground(for: paletteKey)
        }
        return .secondary
    }
}
