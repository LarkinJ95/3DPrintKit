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
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .listRowBackground(Color.clear)
                        }
                    }

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
                                Label("Favorite", systemImage: spool.isFavorite ? "star.fill" : "star")
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
                            .tint(.gray)
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
                }
                .searchable(text: $search, prompt: "Material, brand, color, vendor…")
            }
        }
        .navigationTitle("Spools")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showScanner = true } label: { Label("Scan Spool (NFC)", systemImage: "wave.3.right.circle") }
                    Button { showAddSpool = true } label: { Label("Add Spool", systemImage: "plus") }
                    Divider()
                    NavigationLink { StorageListView() } label: { Label("Storage Locations", systemImage: "shippingbox") }
                    NavigationLink { AMSManageView() } label: { Label("AMS / MMU", systemImage: "square.grid.2x2") }
                    NavigationLink { TransferListView() } label: { Label("Transfers", systemImage: "arrow.left.arrow.right") }
                    NavigationLink { SpoolMatchView() } label: { Label("Find Filament for a Job", systemImage: "magnifyingglass") }
                    NavigationLink { DesiccantListView() } label: { Label("Desiccant", systemImage: "drop") }
                    NavigationLink { WishlistView() } label: { Label("Wishlist", systemImage: "heart") }
                    NavigationLink { PurchaseListView() } label: { Label("Purchases", systemImage: "cart") }
                    Divider()
                    Toggle("Show Archived", isOn: $showArchived)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { showAddSpool = true } label: { Image(systemName: "plus") }
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
        .onChange(of: router.deepLinkSpoolID) { _, id in
            guard let id, let spool = allSpools.first(where: { $0.id == id }) else { return }
            router.deepLinkSpoolID = nil
            linkedSpool = spool
        }
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
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                Text("\(material?.name ?? spool.materialID.uppercased()) · \(spool.finish.displayName)")
                    .font(.caption).foregroundStyle(.secondary)
                if let location = spool.storageLocation {
                    Label(location.name, systemImage: location.kind.systemImage)
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.grams(spool.currentWeightG))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                let status = spool.status(dryingActive: dryingActive)
                StatusBadge(status: status.status, text: status.rawValue)
            }
        }
        .padding(.vertical, 2)
    }
}
