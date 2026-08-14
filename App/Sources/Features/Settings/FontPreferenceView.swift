import SwiftUI
import AppKit
import Domain

// MARK: - NoteFontSection (003 T047/T182, FR-055/055a Rev 3; 2026-08-14)
//
// Per tasks.md T047 and spec FR-055/055a (Rev 3): a SINGLE user-facing
// "Note body font" concept — one choice over the SYSTEM font-family list
// with automatic system fallback for CJK — instead of implementation
// typography terms ("English font"/"Chinese font"). The storage key is
// unchanged (001 FR-043).
//
// Rev 3 (2026-08-14): the control is a native `Picker(.menu)` fed by
// `NSFontManager.availableFontFamilies` — NOT a text field. "System
// Default" is the first option and maps to the unset state (`nil`
// preference = the macOS system font, NOT FontPreference.systemDefault —
// that is only the intra-preference fallback). Selecting a family commits
// immediately (there is no text input, so no draft/commit-on-focus-loss
// path and no Reset button). Because the control is a Picker, the Settings
// window no longer auto-focuses a text field on open. The Preview renders
// a MULTI-LINE bilingual sample and applies the Text Spacing preset's
// line-spacing value, so both typography settings are visible live.

public struct NoteFontSection: View {
    /// The observable preference source (the bootstrap's single instance).
    let typography: TypographyPreferences

    public init(typography: TypographyPreferences) {
        self.typography = typography
    }

    public var body: some View {
        Group {
            // FR-055/055a (Rev 3): the family choice over the system list.
            // LabeledContent gives the form-native label/value column
            // alignment; the menu sits in the value column (bounded width).
            LabeledContent("Note body font") {
                Picker("Note body font", selection: selection) {
                    ForEach(families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 240)
                .help("Choose the font family for note body text. System Default uses the macOS system font; Chinese uses a matching system font automatically.")
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

            // FR-055 (Rev 3): meaningful bilingual MULTI-LINE live preview —
            // the sample spans three lines so the Text Spacing line-spacing
            // effect is actually visible; font family and spacing both
            // update immediately. Aligned to the same value column.
            LabeledContent("Preview") {
                Text(FontPreferenceUI.bilingualPreviewSample)
                    .font(previewFont)
                    .lineSpacing(typography.textSpacing.lineSpacingValue ?? 0)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }

    /// The pickable options: "System Default" + sorted system families
    /// (with the stored family retained when the system no longer provides
    /// it — the selection must never dangle).
    private var families: [String] {
        NoteFontChoicePresentation.options(
            families: NSFontManager.shared.availableFontFamilies,
            storedFamily: typography.fontPreference?.primaryFamily
        )
    }

    /// Maps the stored preference to the menu selection; selecting commits
    /// immediately (each menu pick is a complete valid state).
    private var selection: Binding<String> {
        Binding(
            get: { NoteFontChoicePresentation.selectedOption(for: typography.fontPreference?.primaryFamily) },
            set: { option in
                if let family = NoteFontChoicePresentation.family(from: option) {
                    typography.setFontPreference(FontPreference(
                        primaryFamily: family,
                        fallbackFamily: typography.fontPreference?.fallbackFamily
                            ?? FontPreference.systemDefault.fallbackFamily
                    ))
                } else {
                    // "System Default": clear the stored preference — the
                    // editor falls back to the macOS system font.
                    typography.setFontPreference(nil)
                }
            }
        )
    }

    /// The family the PREVIEW renders with; the system font when unset.
    private var previewFont: Font {
        if let family = typography.fontPreference?.primaryFamily {
            return .custom(family, size: 15, relativeTo: .body)
        }
        return .body
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
