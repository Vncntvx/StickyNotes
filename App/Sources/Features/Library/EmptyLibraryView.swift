import SwiftUI

// MARK: - EmptyLibraryView (T208, FR-014a)
//
// Per tasks.md T208 and spec FR-014a (clarified 2026-08-07): the first-
// launch empty-library variant — a clear call-to-action to create the first
// note (button + keyboard shortcut), plus a brief, dismissible onboarding
// hint explaining auto-save and the menu-bar-primary model. The hint is
// never shown again once `hasCreatedFirstNote` or `dismissed` is set
// (LocalPreferences, T207). Distinct from the unified empty-state (FR-014c).

public struct EmptyLibraryView: View {
    @Bindable var model: LibraryModel
    let createNote: () -> Void

    public init(model: LibraryModel, createNote: @escaping () -> Void) {
        self.model = model
        self.createNote = createNote
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "note.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Welcome to Sticky Notes")
                .font(.title3)

            Button(action: createNote) {
                Label("Create your first note", systemImage: "square.and.pencil")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .keyboardShortcut("n", modifiers: .command)
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Creates a new blank note")

            if model.showOnboardingHint {
                onboardingHint
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var onboardingHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Everything you type is saved automatically — no Save button.", systemImage: "bolt.fill")
            Label("Your notes live in the menu bar. Click the icon to open this library anytime.", systemImage: "menubar.rectangle")
            HStack {
                Spacer()
                Button("Got it") {
                    model.dismissOnboardingHint()
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 420)
        .accessibilityElement(children: .contain)
    }
}
