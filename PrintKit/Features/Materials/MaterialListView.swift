import SwiftUI

/// Offline filament reference database.
struct MaterialListView: View {
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
                    .padding(.horizontal, PK.Spacing.lg)
                    .padding(.vertical, PK.Spacing.xs)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if materials.isEmpty {
                Section {
                    noResults
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(materials) { material in
                        NavigationLink(value: PushDestination.material(material.id)) {
                            MaterialRowView(material: material)
                        }
                    }
                } header: {
                    Text(familyFilter ?? "All Materials")
                }
            }

            Section("Reference Tools") {
                NavigationLink(value: PushDestination.compareMaterials) {
                    Label("Compare Materials", systemImage: "rectangle.split.2x1")
                }
                NavigationLink {
                    MaterialAssistantView()
                } label: {
                    Label("What Should I Print This With?", systemImage: "wand.and.stars")
                }
                NavigationLink {
                    SubstitutionView()
                } label: {
                    Label("Material Substitution", systemImage: "arrow.triangle.swap")
                }
                NavigationLink {
                    CompatibilityMatrixView()
                } label: {
                    Label("Printer Compatibility Matrix", systemImage: "tablecells")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Search materials")
        .navigationTitle("Reference")
    }

    @ViewBuilder
    private var noResults: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label("No Materials", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("Nothing in the reference database matches this family.")
            } actions: {
                Button("Clear Filter") { familyFilter = nil }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct MaterialRowView: View {
    let material: FilamentMaterial

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(material.name).font(.subheadline.weight(.medium))
                if material.hardenedNozzleRequired {
                    Image(systemName: "hexagon.fill")
                        .font(.caption2)
                        .foregroundStyle(PK.StatusColor.attention)
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
