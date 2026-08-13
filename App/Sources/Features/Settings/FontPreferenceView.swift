import SwiftUI
import AppKit
import Domain

// MARK: - NoteFontSection (003 T047, FR-055; Rev 2 2026-08-14)
//
// Per tasks.md T047 and spec FR-055: a SINGLE user-facing "note font"
// concept — one family picker + automatic system fallback for CJK —
// instead of implementation typography terms ("English font"/"Chinese
// font"). The storage key is unchanged (001 FR-043); the default aligns
// with macOS system typography; the preview is meaningfully bilingual
// (Latin + CJK mixed, FR-055).
//
// Rev 2 (2026-08-14, FR-050): no longer its own first-level tab — embedded
// as the General pane's "Notes" section content. Behavior and storage are
// unchanged.

public struct NoteFontSection: View {
    @State private var noteFontFamily: String = Self.currentFamily
    /// 003 T043 (CHK031): a save failure surfaces as a non-blocking
    /// localized notice; user data is never overwritten (the store
    /// validates before writing) and the app continues normally.
    @State private var saveNotice: String?

    private static var currentFamily: String {
        FontPreferenceStore.load()?.primaryFamily ?? FontPreference.systemDefault.primaryFamily ?? ""
    }

    public init() {
        _noteFontFamily = State(initialValue: Self.currentFamily)
    }

    public var body: some View {
        Group {
            // FR-055: ONE "note font" field (no implementation typography
            // terms). The family name persists under the unchanged key.
            TextField("Note font", text: $noteFontFamily)
                .onChange(of: noteFontFamily) { _, _ in persist() }

            // FR-055: meaningful bilingual live preview (Latin + CJK
            // rendered together with the system fallback).
            HStack(spacing: 8) {
                Text(FontPreferenceUI.bilingualPreviewSample)
                    .font(.custom(noteFontFamily, size: 15, relativeTo: .body))
                Spacer()
                Text("Preview")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if let saveNotice {
                Label(saveNotice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func persist() {
        // FR-055: the stored value keeps the primary-family slot; the
        // fallback stays system-provided (nil = system default).
        let preference = FontPreference(
            primaryFamily: noteFontFamily.isEmpty ? nil : noteFontFamily,
            fallbackFamily: FontPreferenceStore.load()?.fallbackFamily ?? FontPreference.systemDefault.fallbackFamily
        )
        // 003 T043 (CHK031): validate BEFORE writing — a failed encode must
        // never overwrite the stored preference; surface non-blockingly.
        guard let data = try? JSONEncoder().encode(preference) else {
            saveNotice = String(localized: "Could not save the font preference. Your existing preference is unchanged.")
            return
        }
        FontPreferenceStore.save(preference)
        _ = data
        saveNotice = nil
    }
}
