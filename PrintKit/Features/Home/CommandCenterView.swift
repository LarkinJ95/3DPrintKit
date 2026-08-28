import SwiftUI

/// Command-palette-inspired universal action sheet (native iOS presentation).
struct CommandCenterView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [QuickAction] {
        if query.isEmpty { return QuickAction.allCases }
        return QuickAction.allCases.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { action in
                Button {
                    dismiss()
                    // Let the sheet dismiss before presenting the next one.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        router.perform(action)
                    }
                } label: {
                    Label(action.title, systemImage: action.systemImage)
                }
            }
            .searchable(text: $query, prompt: "Type a command")
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
