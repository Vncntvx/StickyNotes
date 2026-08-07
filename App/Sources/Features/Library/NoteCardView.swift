import SwiftUI
import Domain

// MARK: - NoteCardView (T162/T244/T256)
//
// Per tasks.md T162/T244/T256 and spec FR-002/FR-002a/FR-020/FR-020a/
// FR-021/FR-072b:
// - Card shows: manual title / generated summary (display-only, FR-045),
//   body preview truncated at 2 rendered lines with a trailing ellipsis
//   drawn from the FIRST rich-text block (never duplicating the summary
//   title — FR-020a), note color, last-modified time (relative within 7
//   days, absolute beyond — FR-020a), todo progress ("completed/total",
//   "99+ completed" above 99 — FR-072b), screenshot/image/file-ref
//   indicators, conflict/sync warning.
// - FR-021: byte-identical first meaningful content MAY produce identical
//   summaries; cards remain distinguishable via the other fields.

/// The card-grid note card.
public struct NoteCardView: View {
    let card: LibraryModel.NoteCardRow
    let action: () -> Void

    public init(card: LibraryModel.NoteCardRow, action: @escaping () -> Void) {
        self.card = card
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
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    if let progress = card.todoProgress {
                        Label(progress, systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if card.hasScreenshot {
                        Image(systemName: "camera")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has screenshot")
                    }
                    if card.hasImage {
                        Image(systemName: "photo")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has image")
                    }
                    if card.hasFileReference {
                        Image(systemName: "doc")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Has file reference")
                    }
                    Spacer(minLength: 0)
                    Text(DisplayFormatters.lastModified(card.modifiedAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            // FR-002a: card height ≈ 160 pt (grid column count handled by
            // LibraryCardGrid; the 2-line title + 2-line preview bounds the
            // content so the height is stable).
            .frame(maxWidth: .infinity, minHeight: 140, maxHeight: LibraryCardGrid.cardApproximateHeight, alignment: .leading)
            .background(cardColor, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var titleText: Text {
        if let title = card.title, !title.isEmpty {
            return Text(title).font(.headline).foregroundStyle(.primary)
        }
        if let summary = card.summary {
            return Text(summary).font(.headline).foregroundStyle(.primary)
        }
        return Text("Untitled note").font(.headline).foregroundStyle(.secondary)
    }

    private var cardColor: Color {
        // FR-040a canonical hexes rendered via the Domain projection.
        let rgb = card.colorKey.builtinRGB
        guard let rgb else { return Color(nsColor: .textBackgroundColor) }
        return Color(
            red: rgb.red,
            green: rgb.green,
            blue: rgb.blue,
            opacity: 1.0
        )
    }
}
