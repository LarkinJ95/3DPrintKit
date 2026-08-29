import SwiftUI
import SwiftData

/// Universal search — one place to reach an action, a spool, a material, or a
/// troubleshooting entry. All four sources are local, so results are instant.
///
/// Replaces the old Command Center, which searched only the twelve action
/// titles and left the rest of the app unreachable from here.
struct SearchView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Spool.lastUsedDate, order: .reverse) private var spools: [Spool]

    @State private var query = ""

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var actions: [QuickAction] {
        guard !trimmed.isEmpty else { return QuickAction.allCases }
        return QuickAction.allCases.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    private var matchedSpools: [Spool] {
        guard !trimmed.isEmpty else { return [] }
        return spools.filter { spool in
            guard !spool.isArchived else { return false }
            let haystack = [spool.manufacturer, spool.productLine, spool.colorName,
                            spool.materialID, spool.vendor, spool.lotNumber]
                .joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var matchedMaterials: [FilamentMaterial] {
        guard !trimmed.isEmpty else { return [] }
        return MaterialLibrary.shared.search(trimmed)
    }

    private var matchedIssues: [TroubleshootingIssue] {
        guard !trimmed.isEmpty else { return [] }
        return TroubleshootingLibrary.issues.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed) ||
            $0.symptoms.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var hasResults: Bool {
        !actions.isEmpty || !matchedSpools.isEmpty || !matchedMaterials.isEmpty || !matchedIssues.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !matchedSpools.isEmpty {
                    Section("Spools") {
                        ForEach(matchedSpools.prefix(6)) { spool in
                            resultButton {
                                router.openSpool(spool.id)
                            } label: {
                                SpoolResultRow(spool: spool)
                            }
                        }
                    }
                }

                if !matchedMaterials.isEmpty {
                    Section("Materials") {
                        ForEach(matchedMaterials.prefix(6)) { material in
                            resultButton {
                                router.push(.material(material.id), on: .materials)
                            } label: {
                                ResultRow(symbol: "square.stack.3d.up",
                                          title: material.name,
                                          detail: material.tagline)
                            }
                        }
                    }
                }

                if !matchedIssues.isEmpty {
                    Section("Troubleshooting") {
                        ForEach(matchedIssues.prefix(6)) { issue in
                            resultButton {
                                router.push(.troubleshootIssue(issue.id), on: .tools)
                            } label: {
                                ResultRow(symbol: "stethoscope",
                                          title: issue.title,
                                          detail: issue.symptoms)
                            }
                        }
                    }
                }

                if !actions.isEmpty {
                    Section {
                        ForEach(actions) { action in
                            resultButton {
                                router.perform(action)
                            } label: {
                                Label(action.title, systemImage: action.systemImage)
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text(trimmed.isEmpty ? "Actions" : "Matching Actions")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if !hasResults {
                    ContentUnavailableView.search(text: trimmed)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Spools, materials, problems, actions")
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    /// Dismiss first, then route — presenting a sheet while one is still
    /// on screen is dropped by UIKit.
    @ViewBuilder
    private func resultButton<Content: View>(_ route: @escaping () -> Void,
                                             @ViewBuilder label: () -> Content) -> some View {
        Button {
            dismiss()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                route()
            }
        } label: {
            label()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Result rows

private struct ResultRow: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            Image(systemName: symbol)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct SpoolResultRow: View {
    let spool: Spool

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            SpoolRingView(fraction: spool.remainingFraction, filamentColor: spool.color, lineWidth: 5)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(spool.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                Text(Format.grams(spool.currentWeightG))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
