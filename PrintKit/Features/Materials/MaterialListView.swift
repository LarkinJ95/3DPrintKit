import SwiftUI

/// Offline filament reference database.
struct MaterialListView: View {
    @Environment(AppRouter.self) private var router
    @State private var search = ""
    @State private var familyFilter: String?

    private var families: [String] {
        Array(Set(MaterialLibrary.shared.materials.map(\.family))).sorted()
    }

    private var materials: [FilamentMaterial] {
        MaterialLibrary.shared.search(search).filter {
            familyFilter == nil || $0.family == familyFilter
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PK.Spacing.sm) {
                        SelectableChip(title: "All", isSelected: familyFilter == nil) { familyFilter = nil }
                        ForEach(families, id: \.self) { family in
                            SelectableChip(title: family, isSelected: familyFilter == family) { familyFilter = family }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }

            ForEach(materials) { material in
                NavigationLink {
                    MaterialDetailView(material: material)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(material.name).font(.subheadline.weight(.medium))
                            if material.hardenedNozzleRequired {
                                Image(systemName: "hexagon.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .accessibilityLabel("Hardened nozzle required")
                            }
                        }
                        Text(material.tagline).font(.caption).foregroundStyle(.secondary)
                        Text("\(material.nozzleRangeText) · Bed \(material.bedRangeText)")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .searchable(text: $search, prompt: "Search materials")
        .navigationTitle("Materials")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    NavigationLink { MaterialCompareView() } label: {
                        Label("Compare Materials", systemImage: "rectangle.split.2x1")
                    }
                    NavigationLink { MaterialAssistantView() } label: {
                        Label("What Should I Print This With?", systemImage: "wand.and.stars")
                    }
                    NavigationLink { SubstitutionView() } label: {
                        Label("Material Substitution", systemImage: "arrow.triangle.swap")
                    }
                    NavigationLink { CompatibilityMatrixView() } label: {
                        Label("Printer Compatibility Matrix", systemImage: "tablecells")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            if router.quickAction == .compareMaterials { router.clearQuickAction() }
        }
    }
}
