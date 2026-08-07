import SwiftUI

// MARK: - AboutView (T144/T172, FR-008)
//
// Per tasks.md T144/T172 and spec FR-008: the About panel is reachable from
// the menu-bar interface (covers About reachability when the Dock icon is
// disabled).

public struct AboutView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.tint)

            Text("Sticky Notes")
                .font(.title2)

            Text("Local-first sticky notes for the menu bar. Working title.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(28)
        .frame(width: 320)
        .accessibilityElement(children: .combine)
    }
}
