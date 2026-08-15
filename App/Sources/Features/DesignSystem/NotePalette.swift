import SwiftUI
import Domain

// MARK: - NotePalette (003 T007, FR-030/FR-031/FR-032/FR-033)
//
// Per tasks.md T007 and spec FR-030..FR-033 / data-model.md:
// - Seven built-in colors: yellow/peach/pink/green/blue/lavender/gray
//   (FR-030), each with INDEPENDENTLY designed light and dark values
//   (FR-031 — no mechanical transparency/brightness transforms; the values
//   below are per-appearance design choices).
// - Every light/dark combination satisfies 001 FR-042 thresholds against
//   its rendered background: primary text ≥4.5:1, large text/active
//   controls ≥3:1, secondary text ≥4.5:1, selection/control states ≥3:1.
//   `contrastValidated` records that the entry passed the threshold checks
//   (asserted by PaletteContrastTests against resolved sRGB values).
// - FR-032: the old six stored colors map semantically onto the new
//   palette (黄→黄、粉→粉、紫→薰衣草、蓝→蓝、绿→绿、灰→灰); custom colors
//   are preserved byte-exact and never enter the palette.
// - FR-033: foreground auto-adjustment picks black/white per appearance so
//   custom-color + transparency + Increase Contrast combinations are never
//   rejected (the palette-driven foreground; ReadableTheme applies it).
// - Colors are APP CONSTANTS, never persisted (data-model.md §呈现层实体).

// MARK: - Presentation color keys

/// The seven presentation palette keys (FR-030). Distinct from the Domain
/// `NoteColorKey` (which has six built-ins + custom): peach and lavender
/// are presentation-level identities introduced by this redesign.
public enum NotePaletteKey: String, Sendable, Hashable, CaseIterable, Codable {
    case yellow
    case peach
    case pink
    case green
    case blue
    case lavender
    case gray
}

/// A single palette entry: designed light/dark background values, the
/// auto-adjusted foregrounds, and the FR-031 validation marker.
public struct NotePaletteEntry: Sendable, Equatable {
    public let key: NotePaletteKey
    /// Designed light-mode background (independent design, FR-031).
    public let lightColor: Color
    /// Designed dark-mode background (independent design, FR-031).
    public let darkColor: Color
    /// FR-031 threshold validation marker (asserted by tests against
    /// resolved rendered values).
    public let contrastValidated: Bool

    public init(
        key: NotePaletteKey,
        lightColor: Color,
        darkColor: Color,
        contrastValidated: Bool
    ) {
        self.key = key
        self.lightColor = lightColor
        self.darkColor = darkColor
        self.contrastValidated = contrastValidated
    }
}

// MARK: - Palette

/// The single source of note-surface colors (FR-030..FR-033).
public enum NotePalette {

    /// The seven palette entries, light/dark designed per appearance.
    public static let entries: [NotePaletteEntry] = [
        NotePaletteEntry(
            key: .yellow,
            lightColor: Color(red: 1.000, green: 0.878, blue: 0.541),
            darkColor: Color(red: 0.420, green: 0.365, blue: 0.125),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .peach,
            lightColor: Color(red: 1.000, green: 0.788, blue: 0.659),
            darkColor: Color(red: 0.478, green: 0.290, blue: 0.180),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .pink,
            lightColor: Color(red: 0.976, green: 0.659, blue: 0.769),
            darkColor: Color(red: 0.478, green: 0.231, blue: 0.322),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .green,
            lightColor: Color(red: 0.659, green: 0.910, blue: 0.722),
            darkColor: Color(red: 0.180, green: 0.353, blue: 0.243),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .blue,
            lightColor: Color(red: 0.659, green: 0.812, blue: 0.976),
            darkColor: Color(red: 0.180, green: 0.290, blue: 0.420),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .lavender,
            lightColor: Color(red: 0.788, green: 0.659, blue: 0.910),
            darkColor: Color(red: 0.290, green: 0.231, blue: 0.420),
            contrastValidated: true
        ),
        NotePaletteEntry(
            key: .gray,
            lightColor: Color(red: 0.847, green: 0.847, blue: 0.863),
            darkColor: Color(red: 0.227, green: 0.227, blue: 0.243),
            contrastValidated: true
        ),
    ]

    /// Returns the entry for a palette key (always exists — the palette is
    /// closed over the seven keys).
    public static func entry(for key: NotePaletteKey) -> NotePaletteEntry {
        entries.first { $0.key == key }!
    }

    /// FR-032: maps a stored Domain color key onto the presentation
    /// palette. `.custom` returns nil (custom colors never enter the
    /// palette); old purple maps semantically to lavender.
    public static func paletteKey(for domainKey: NoteColorKey) -> NotePaletteKey? {
        switch domainKey {
        case .yellow: return .yellow
        case .pink:   return .pink
        case .purple: return .lavender  // FR-032 紫→薰衣草
        case .blue:   return .blue
        case .green:  return .green
        case .gray:   return .gray
        case .custom: return nil
        }
    }

    /// The palette background as a DYNAMIC color (auto-switches light/dark
    /// with the system appearance) — the rendering path used by views.
    public static func dynamicColor(for key: NotePaletteKey) -> Color {
        let entry = entry(for: key)
        return Color(nsColor: NSColor(name: nil) { appearance in
            (appearance.name == .darkAqua ? entry.darkColor : entry.lightColor)
                .resolvedSRGBColor()
        })
    }

    /// The readable foreground (black/white auto-adjustment, FR-033) for a
    /// key in the given appearance. Chosen by contrast against the designed
    /// background — never rejects the color.
    public static func foreground(for key: NotePaletteKey, appearanceName: NSAppearance.Name) -> Color {
        let entry = entry(for: key)
        let bg = resolvedSRGB(appearanceName == .darkAqua ? entry.darkColor : entry.lightColor)
        let fg = NoteAppearanceContrast.readableForeground(forBackground: bg)
        return Color(
            red: fg.red,
            green: fg.green,
            blue: fg.blue,
            opacity: 1.0
        )
    }

    /// The readable foreground as a DYNAMIC color (auto-switches with the
    /// system appearance) — the rendering path used by views.
    public static func dynamicForeground(for key: NotePaletteKey) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            foreground(for: key, appearanceName: appearance.name).resolvedSRGBColor()
        })
    }

    /// The secondary text color for a key in the given appearance — the
    /// readable foreground at 90% opacity, which keeps secondary text
    /// ≥4.5:1 on every designed background (validated by the contrast
    /// tests).
    public static func secondaryForeground(for key: NotePaletteKey, appearanceName: NSAppearance.Name) -> Color {
        let entry = entry(for: key)
        let bg = resolvedSRGB(appearanceName == .darkAqua ? entry.darkColor : entry.lightColor)
        let fg = NoteAppearanceContrast.readableForeground(forBackground: bg)
        return Color(
            red: fg.red,
            green: fg.green,
            blue: fg.blue,
            opacity: 0.9
        )
    }

    /// The secondary foreground as a DYNAMIC color (auto-switches with the
    /// system appearance) — the rendering path used by views.
    public static func dynamicSecondaryForeground(for key: NotePaletteKey) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            secondaryForeground(for: key, appearanceName: appearance.name).resolvedSRGBColor()
        })
    }

    /// Resolves a SwiftUI color to sRGB components via AppKit (the
    /// "rendered" value the FR-042 thresholds apply to).
    static func resolvedSRGB(_ color: Color) -> Domain.RGBColor {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else {
            return Domain.RGBColor(red: 0, green: 0, blue: 0)
        }
        return Domain.RGBColor(
            red: Double(ns.redComponent),
            green: Double(ns.greenComponent),
            blue: Double(ns.blueComponent)
        )
    }
}

extension Color {
    /// Resolves this color to an sRGB NSColor in the CURRENT drawing
    /// appearance (used by dynamic NSColor providers).
    fileprivate func resolvedSRGBColor() -> NSColor {
        NSColor(self).usingColorSpace(.sRGB) ?? .clear
    }
}
