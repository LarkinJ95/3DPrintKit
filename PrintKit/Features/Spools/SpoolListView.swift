import SwiftUI
import SwiftData

struct SpoolListView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query(sort: \Spool.lastUsedDate, order: .reverse) private var allSpools: [Spool]
    @Query private var sessions: [DryingSession]

    @State private var search = ""
    @State private var materialFilter: String?
    @State private var showArchived = false
    @State private var showAddSpool = false
    @State private var showScanner = false
    @State private var spoolToDelete: Spool?
    @State private var linkedSpool: Spool?

    private var activeDryingSpoolIDs: Set<UUID> {
        Set(sessions.filter(\.isActive).compactMap { $0.spool?.id })
    }

    private var spools: [Spool] {
        allSpools.filter { spool in
            if !showArchived && spool.isArchived { return false }
            if let materialFilter, spool.materialID != materialFilter { return false }
            if !search.isEmpty {
                let q = search.lowercased()
                let haystack = [spool.manufacturer, spool.productLine, spool.colorName,
                                spool.materialID, spool.vendor, spool.lotNumber].joined(separator: " ").lowercased()
                if !haystack.contains(q) { return false }
            }
            return true
        }
    }

    private var materialsInUse: [FilamentMaterial] {
        let ids = Set(allSpools.map(\.materialID))
        return MaterialLibrary.shared.materials.filter { ids.contains($0.id) }
    }

    private var isFiltered: Bool { !search.isEmpty || materialFilter != nil }

    private var totalGrams: Double {
        spools.reduce(0) { $0 + $1.currentWeightG }
    }

    var body: some View {
        Group {
            if allSpools.isEmpty {
                PKEmptyState(symbol: "circle.dashed",
                             title: "No Spools Yet",
                             message: "Add a spool to track filament, drying, prints, and NFC tags.",
                             actionTitle: "Add Spool") {
                    showAddSpool = true
                }
            } else {
                list
            }
        }
        .navigationTitle("Inventory")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showScanner = true } label: {
                    Image(systemName: "wave.3.right")
                }
                .accessibilityLabel("Scan spool tag")
                Button { showAddSpool = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add spool")
            }
        }
        .sheet(isPresented: $showAddSpool) {
            NavigationStack { SpoolFormView(spool: nil) }
        }
        .sheet(isPresented: $showScanner) {
            NavigationStack { NFCScanView() }
        }
        .alert("Delete Spool?", isPresented: .constant(spoolToDelete != nil)) {
            Button("Delete", role: .destructive) {
                if let spool = spoolToDelete {
                    context.delete(spool)
                    Haptics.warning()
                }
                spoolToDelete = nil
            }
            Button("Cancel", role: .cancel) { spoolToDelete = nil }
        } message: {
            Text("This permanently removes the spool and detaches it from print history. Prints already logged keep their material and grams.")
        }
        .navigationDestination(item: $linkedSpool) { spool in
            SpoolDetailView(spool: spool)
        }
        .onChange(of: router.deepLinkSpoolID) { _, _ in openDeepLinkedSpool() }
        .onAppear { openDeepLinkedSpool() }
    }

    private var list: some View {
        List {
            if !materialsInUse.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: PK.Spacing.sm) {
                            SelectableChip(title: "All", isSelected: materialFilter == nil) { materialFilter = nil }
                            ForEach(materialsInUse) { material in
                                SelectableChip(title: material.name, isSelected: materialFilter == material.id) {
                                    materialFilter = material.id
                                }
                            }
                        }
                        .padding(.horizontal, PK.Spacing.lg)
                        .padding(.vertical, PK.Spacing.xs)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if spools.isEmpty {
                Section {
                    noResults
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                Section {
                    ForEach(spools) { spool in
                        NavigationLink {
                            SpoolDetailView(spool: spool)
                        } label: {
                            SpoolRowView(spool: spool, dryingActive: activeDryingSpoolIDs.contains(spool.id))
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                spool.isFavorite.toggle()
                                Haptics.light()
                            } label: {
                                Label("Favorite", systemImage: spool.isFavorite ? "star.slash" : "star")
                            }
                            .tint(.yellow)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                spoolToDelete = spool
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            archiveButton(for: spool)
                        }
                        .contextMenu {
                            Button { router.perform(.logPrint) } label: { Label("Use for Print", systemImage: "printer") }
                            Button { router.perform(.startDrying) } label: { Label("Start Drying", systemImage: "humidity") }
                            Button { router.perform(.writeNFC) } label: { Label("Write NFC", systemImage: "wave.3.right") }
                            Divider()
                            Button { duplicate(spool) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                            Button { spool.isArchived.toggle() } label: { Label(spool.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox") }
                            Button(role: .destructive) { markEmpty(spool) } label: { Label("Mark Empty", systemImage: "circle.slash") }
                        }
                    }
                } header: {
                    HStack {
                        Text(isFiltered ? "\(spools.count) Match\(spools.count == 1 ? "" : "es")" : "Spools")
                        Spacer()
                        Text(Format.grams(totalGrams))
                            .monospacedDigit()
                            .textCase(nil)
                    }
                }
            }

            // The inventory features that used to hide in the overflow menu.
            Section("Inventory") {
                inventoryLink("Storage Locations", "shippingbox") { StorageListView() }
                inventoryLink("AMS / MMU", "square.grid.2x2") { AMSManageView() }
                inventoryLink("Transfers", "arrow.left.arrow.right") { TransferListView() }
                inventoryLink("Find Filament for a Job", "magnifyingglass") { SpoolMatchView() }
                inventoryLink("Desiccant", "drop") { DesiccantListView() }
                inventoryLink("Wishlist", "heart") { WishlistView() }
                inventoryLink("Purchases", "cart") { PurchaseListView() }
                Toggle(isOn: $showArchived) {
                    Label("Show Archived Spools", systemImage: "archivebox")
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $search, prompt: "Material, brand, color, vendor…")
        .refreshable {
            await SyncEngine.shared.syncNow(context: context)
        }
    }

    @ViewBuilder
    private var noResults: some View {
        if !search.isEmpty {
            ContentUnavailableView.search(text: search)
        } else {
            ContentUnavailableView {
                Label("No Spools Match", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text(materialFilter.flatMap { MaterialLibrary.shared.material(for: $0)?.name }
                        .map { "You have no \($0) spools in stock." }
                     ?? "Nothing matches the current filter.")
            } actions: {
                Button("Clear Filter") { materialFilter = nil }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    @ViewBuilder
    private func inventoryLink<Destination: View>(_ title: String, _ symbol: String,
                                                  @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            Label(title, systemImage: symbol)
        }
    }

    private func openDeepLinkedSpool() {
        guard let id = router.deepLinkSpoolID,
              let spool = allSpools.first(where: { $0.id == id }) else { return }
        router.deepLinkSpoolID = nil
        linkedSpool = spool
    }

    private func duplicate(_ spool: Spool) {
        let copy = Spool()
        copy.manufacturer = spool.manufacturer
        copy.productLine = spool.productLine
        copy.materialID = spool.materialID
        copy.colorName = spool.colorName
        copy.colorHex = spool.colorHex
        copy.finish = spool.finish
        copy.diameter = spool.diameter
        copy.originalNetWeightG = spool.originalNetWeightG
        copy.currentWeightG = spool.originalNetWeightG
        copy.emptySpoolWeightG = spool.emptySpoolWeightG
        copy.cost = spool.cost
        copy.vendor = spool.vendor
        context.insert(copy)
        Haptics.success()
    }

    private func markEmpty(_ spool: Spool) {
        spool.currentWeightG = 0
        spool.lastUsedDate = Date()
    }

    private func archiveButton(for spool: Spool) -> some View {
        Button {
            spool.isArchived.toggle()
        } label: {
            Label(
                spool.isArchived ? "Unarchive" : "Archive",
                systemImage: spool.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.gray)
    }
}

struct SpoolRowView: View {
    let spool: Spool
    var dryingActive: Bool = false

    private var material: FilamentMaterial? {
        MaterialLibrary.shared.material(for: spool.materialID)
    }

    var body: some View {
        HStack(spacing: PK.Spacing.md) {
            SpoolRingView(fraction: spool.remainingFraction, filamentColor: spool.color, lineWidth: 6)
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spool.displayName).font(.subheadline.weight(.medium)).lineLimit(1)
                    if spool.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                Text("\(material?.name ?? spool.materialID.uppercased()) · \(spool.finish.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                if let location = spool.storageLocation {
                    Label(location.name, systemImage: location.kind.systemImage)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: PK.Spacing.sm)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Format.grams(spool.currentWeightG))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                let status = spool.status(dryingActive: dryingActive)
                StatusBadge(status: status.status, text: status.rawValue)
            }
        }
        .padding(.vertical, 2)
    }
}
