import SwiftUI
import AppKit
import Domain

// MARK: - NoteFontSection (003 T047, FR-055; Rev 2/Phase 5 2026-08-14)
//
// Per tasks.md T047 and spec FR-055: a SINGLE user-facing "note font"
// concept — one family field + automatic system fallback for CJK —
// instead of implementation typography terms ("English font"/"Chinese
// font"). The storage key is unchanged (001 FR-043).
//
// Phase 5 (2026-08-14): the field is a LOCAL DRAFT — commits to the
// observable `TypographyPreferences` only on submit / focus loss / Reset,
// so typing a family name never restyles every open note per keystroke.
// The empty field IS the default state: `nil` preference = the macOS
// system font (NOT FontPreference.systemDefault — that is only the
// intra-preference fallback, and displaying it when unset was an existing
// display/render mismatch this section now fixes). The Text Spacing row
// commits immediately (each tap is a complete valid state).

public struct NoteFontSection: View {
    /// The observable preference source (the bootstrap's single instance).
    let typography: TypographyPreferences

    /// The LOCAL draft of the family name — committed on submit/focus loss.
    @State private var draftFamily: String = ""
    /// Whether the draft differs from the committed preference.
    @State private var isDirty = false
    /// 003 T043 (CHK031): a save failure surfaces as a non-blocking
    /// localized notice; user data is never overwritten and the app
    /// continues normally.
    @State private var saveNotice: String?
    /// The field's focus state (commit on focus loss).
    @FocusState private var familyFieldFocused: Bool

    public init(typography: TypographyPreferences) {
        self.typography = typography
        _draftFamily = State(initialValue: typography.fontPreference?.primaryFamily ?? "")
    }

    public var body: some View {
        Group {
            // FR-055: ONE "note font" field (no implementation typography
            // terms). The family name persists under the unchanged key.
            // Polish round 2/3: LabeledContent rows give the form-native
            // label/value column alignment — the field sits in the value
            // column (trailing, bounded width) and the preview aligns to
            // the same column; roundedBorder keeps the real interaction
            // (direct typing) visibly editable.
            LabeledContent("Note font") {
                HStack(spacing: 8) {
                    TextField("", text: $draftFamily, prompt: Text("Default"))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .focused($familyFieldFocused)
                        .help("Type a font family name — for example, Helvetica Neue. Empty means Default (the system font).")
                        .onSubmit { commitDraft() }
                        .onChange(of: familyFieldFocused) { _, focused in
                            if !focused { commitDraft() }
                        }
                    Button("Reset") {
                        draftFamily = ""
                        typography.setFontPreference(nil)
                        isDirty = false
                        saveNotice = nil
                    }
                    .disabled(draftFamily.isEmpty && typography.fontPreference == nil)
                }
            }

            // Phase 4/5: the three global text-spacing presets — a
            // presentation preference (never document content). Segmented
            // taps commit immediately.
            LabeledContent("Text Spacing") {
                Picker("Text Spacing", selection: Binding(
                    get: { typography.textSpacing },
                    set: { typography.setTextSpacing($0) }
                )) {
                    ForEach(TextSpacingPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 240)
            }

            // FR-055: meaningful bilingual live preview (Latin + CJK
            // rendered together with the system fallback), aligned to the
            // same value column as the field.
            LabeledContent("Preview") {
                Text(FontPreferenceUI.bilingualPreviewSample)
                    .font(.custom(committedFamily, size: 15, relativeTo: .body))
            }

            if let saveNotice {
                Label(saveNotice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// The family the PREVIEW renders with (the committed preference, or
    /// the system font when unset — empty means Default, not a literal
    /// family name).
    private var committedFamily: String {
        typography.fontPreference?.primaryFamily ?? ""
    }

    private func commitDraft() {
        let family = draftFamily.trimmingCharacters(in: .whitespacesAndNewlines)
        draftFamily = family
        if family.isEmpty {
            typography.setFontPreference(nil)
            saveNotice = nil
            return
        }
        // Validate the family exists before committing (render-time
        // fallback stays as the safety net for any race).
        guard NSFont(name: family, size: 13) != nil else {
            saveNotice = String(localized: "That font family was not found on this Mac. Your existing preference is unchanged.")
            return
        }
        let preference = FontPreference(
            primaryFamily: family,
            fallbackFamily: typography.fontPreference?.fallbackFamily ?? FontPreference.systemDefault.fallbackFamily
        )
        // 003 T043 (CHK031): validate BEFORE writing — a failed encode must
        // never overwrite the stored preference; surface non-blockingly.
        guard (try? JSONEncoder().encode(preference)) != nil else {
            saveNotice = String(localized: "Could not save the font preference. Your existing preference is unchanged.")
            return
        }
        typography.setFontPreference(preference)
        saveNotice = nil
    }
}

extension TextSpacingPreset {
    /// The user-facing display name (Compact / Default / Relaxed).
    var displayName: String {
        switch self {
        case .compact: return String(localized: "Compact")
        case .standard: return String(localized: "Default")
        case .relaxed: return String(localized: "Relaxed")
        }
    }
}
