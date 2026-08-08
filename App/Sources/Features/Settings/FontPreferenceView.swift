import SwiftUI
import AppKit
import Domain

// MARK: - FontPreferenceView (T172, FR-043)
//
// Per tasks.md T172 and spec FR-043: a global font preference with Chinese +
// English fallback (the Domain `FontPreference` model). Primary (Latin)
// family + fallback (CJK) family, persisted via App Group UserDefaults.

public struct FontPreferenceView: View {
    @State private var primaryFamily: String = FontPreference.systemDefault.primaryFamily ?? ""
    @State private var fallbackFamily: String = FontPreference.systemDefault.fallbackFamily ?? ""

    public init() {
        if let preference = FontPreferenceStore.load() {
            _primaryFamily = State(initialValue: preference.primaryFamily ?? FontPreference.systemDefault.primaryFamily ?? "")
            _fallbackFamily = State(initialValue: preference.fallbackFamily ?? FontPreference.systemDefault.fallbackFamily ?? "")
        }
    }

    public var body: some View {
        Form {
            Text("Global font preference. Chinese text uses the fallback family automatically (FR-043).")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("English font", text: $primaryFamily)
                .onChange(of: primaryFamily) { _, _ in persist() }

            TextField("Chinese font", text: $fallbackFamily)
                .onChange(of: fallbackFamily) { _, _ in persist() }

            HStack {
                Text("Aa 中文 Preview")
                    .font(.custom(primaryFamily, size: 15, relativeTo: .body))
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(20)
    }

    private func persist() {
        FontPreferenceStore.save(FontPreference(
            primaryFamily: primaryFamily.isEmpty ? nil : primaryFamily,
            fallbackFamily: fallbackFamily.isEmpty ? nil : fallbackFamily
        ))
    }
}
