import Foundation
import Observation
import Domain

// MARK: - TextSpacingPreset (Phase 2, 2026-08-14)

/// The three global text-spacing presets — a device-local PRESENTATION
/// preference (like the font preference), never document content: it lives
/// only in UserDefaults and, at render time, as an `NSParagraphStyle` on
/// the editor's text storage. It never enters the canonical document, the
/// block payload, JSON/Markdown export, or the sync payload.
public enum TextSpacingPreset: String, Codable, CaseIterable, Sendable, Equatable {
    case compact
    case standard
    case relaxed

    /// The line-spacing metric applied as `NSParagraphStyle.lineSpacing`.
    /// `nil` = write no paragraph style at all (the standard preset keeps
    /// the current TextKit-default metrics byte-for-byte). The compact /
    /// relaxed values are PROTOTYPE constants for visual tuning — they are
    /// not architecture decisions (9/13/24 pt × Latin/CJK/emoji acceptance
    /// decides the final values). Shared single source: the editor
    /// (`EditorTypography.lineSpacing`) and the Settings preview both
    /// consume it (FR-055 Rev 3).
    public var lineSpacingValue: CGFloat? {
        switch self {
        case .compact: return -1.5
        case .standard: return nil
        case .relaxed: return 4.0
        }
    }
}

// MARK: - EditorTypography (Phase 2, 2026-08-14)

/// The resolved typography for one editor — a pure Equatable value. The
/// SwiftUI view layer reads the observable `TypographyPreferences` and
/// computes this value; the editor subtree receives the VALUE only and
/// never touches UserDefaults or the preference object.
///
/// `fontPreference == nil` means the macOS system font — deliberately
/// distinct from an explicit `FontPreference.systemDefault` (Helvetica
/// Neue / PingFang SC), which is only the intra-preference fallback for
/// missing families. Reset must therefore clear the stored preference,
/// not write the systemDefault value.
public struct EditorTypography: Equatable, Sendable {
    /// The global font preference; `nil` = the macOS system font.
    public var fontPreference: FontPreference?
    /// The global text-spacing preset.
    public var textSpacing: TextSpacingPreset
    /// The PER-NOTE text size (never a global setting — FR-043a).
    public var textSize: CGFloat

    public init(
        fontPreference: FontPreference?,
        textSpacing: TextSpacingPreset,
        textSize: CGFloat
    ) {
        self.fontPreference = fontPreference
        self.textSpacing = textSpacing
        self.textSize = textSize
    }

    /// The system typography (system font + standard spacing) at a given
    /// per-note size — the value used by tests and simple view construction.
    public static func system(textSize: CGFloat) -> EditorTypography {
        EditorTypography(fontPreference: nil, textSpacing: .standard, textSize: textSize)
    }

    /// The spacing metric applied as `NSParagraphStyle.lineSpacing` — the
    /// single source is `TextSpacingPreset.lineSpacingValue` (shared with
    /// the Settings preview, FR-055 Rev 3). `nil` = no paragraph style.
    public var lineSpacing: CGFloat? {
        textSpacing.lineSpacingValue
    }
}

// MARK: - TextSpacingPreferenceStore (Phase 2)

/// Device-local storage of the text-spacing preset — the same shape as
/// `FontPreferenceStore` (standard UserDefaults domain, one key).
public enum TextSpacingPreferenceStore {
    /// The persistence key (rawValue string of `TextSpacingPreset`).
    public static let key = "local.stickynotes.textSpacing"

    /// The stored preset; `.standard` when nothing is stored or the raw
    /// value is unrecognized (read-time fallback — no migration).
    public static func load() -> TextSpacingPreset {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let preset = TextSpacingPreset(rawValue: raw) else {
            return .standard
        }
        return preset
    }

    public static func save(_ preset: TextSpacingPreset) {
        UserDefaults.standard.set(preset.rawValue, forKey: key)
    }

    public static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// MARK: - TypographyPreferences (Phase 2)

/// The SINGLE observable source of the global typography preferences
/// (font family + text spacing), composed at bootstrap into
/// `AppEnvironment.typography` (non-optional) and shared by Settings and
/// every note window — no `.shared` fallback, no per-view instances.
///
/// `@unchecked Sendable` mirrors the `LocalPreferences` precedent: the two
/// stored properties are only mutated on the MainActor (UI paths), and
/// UserDefaults is thread-safe.
@Observable
public final class TypographyPreferences: @unchecked Sendable {
    /// The global font preference; `nil` = macOS system font.
    public private(set) var fontPreference: FontPreference?
    /// The global text-spacing preset.
    public private(set) var textSpacing: TextSpacingPreset

    public init(fontPreference: FontPreference? = nil, textSpacing: TextSpacingPreset = .standard) {
        self.fontPreference = fontPreference
        self.textSpacing = textSpacing
    }

    /// Loads the persisted state — the bootstrap's single-instance factory.
    public static func load() -> TypographyPreferences {
        TypographyPreferences(
            fontPreference: FontPreferenceStore.load(),
            textSpacing: TextSpacingPreferenceStore.load()
        )
    }

    /// Sets the font preference. `nil` clears the stored key — the editor
    /// falls back to the macOS system font (Reset semantics).
    public func setFontPreference(_ preference: FontPreference?) {
        if let preference {
            FontPreferenceStore.save(preference)
        } else {
            FontPreferenceStore.clear()
        }
        fontPreference = preference
    }

    public func setTextSpacing(_ preset: TextSpacingPreset) {
        TextSpacingPreferenceStore.save(preset)
        textSpacing = preset
    }
}
