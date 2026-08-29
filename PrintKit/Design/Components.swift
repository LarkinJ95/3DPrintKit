import SwiftUI
import PhotosUI

// MARK: - Keyboard dismissal
//
// The numeric keypads have no return key, so a field that opens one can only
// be left by tapping elsewhere. Every screen with a numeric field applies
// `.pkDismissableKeyboard()` once, which installs a single Done button.

enum PKKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

extension View {
    /// Adds a Done button above the keyboard and lets a scroll drag dismiss it.
    /// Apply once per screen, on the `Form` or `List` itself.
    func pkDismissableKeyboard() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { PKKeyboard.dismiss() }
                        .fontWeight(.semibold)
                }
            }
    }
}

// MARK: - Numeric field row
//
// Replaces the hand-built `HStack { Text; Spacer; TextField.frame(width:) }`
// pattern. `LabeledContent` sizes the field itself and reflows to a stacked
// layout at accessibility text sizes instead of truncating.

struct PKNumericField: View {
    let label: String
    @Binding var value: Double
    var unit: String? = nil
    var placeholder: String = "0"
    var keyboard: UIKeyboardType = .decimalPad

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                TextField(placeholder, value: $value, format: .number)
                    .keyboardType(keyboard)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let unit {
                    Text(unit)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(unit.map { "\(label), in \($0)" } ?? label)
    }
}

// MARK: - Status badge
//
// The label is drawn at full contrast and the hue is carried by the symbol.
// Tinting caption-size text with a system semantic color over a 12% wash of
// the same color lands near 2:1 — well under the 4.5:1 minimum.

struct StatusBadge: View {
    let status: PKStatus
    var text: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
                .font(.caption2)
                .foregroundStyle(status.color)
            Text(text ?? status.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(status.color.opacity(0.22), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text ?? status.label)")
    }
}

// MARK: - Callout (inline advisory inside a list or card)

struct PKCallout: View {
    let status: PKStatus
    let message: String
    var symbol: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PK.Spacing.sm) {
            Image(systemName: symbol ?? status.systemImage)
                .font(.caption)
                .foregroundStyle(status.color)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Empty state (symbol + explanation + action)

struct PKEmptyState: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Metric (large number, prioritized over unit)

struct MetricView: View {
    let label: String
    let value: String
    var unit: String? = nil
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(valueColor)
                if let unit {
                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Key/value row

struct KeyValueRow: View {
    let key: String
    let value: String
    var source: DataSource? = nil

    var body: some View {
        LabeledContent {
            HStack(spacing: PK.Spacing.sm) {
                if let source {
                    SourceTag(source: source)
                }
                Text(value)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.primary)
            }
        } label: {
            Text(key)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}

// MARK: - Data source tag (Manufacturer / Reference / Community / Personal)

enum DataSource: String, CaseIterable, Codable {
    case manufacturer = "Manufacturer"
    case reference = "Reference"
    case community = "Community"
    case personal = "Personal"
}

struct SourceTag: View {
    let source: DataSource

    var body: some View {
        Text(source.rawValue.uppercased())
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .foregroundStyle(.secondary)
            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Data source: \(source.rawValue)")
    }
}

// MARK: - Rating bar (1...5)

struct RatingBar: View {
    let value: Int   // 1...5
    var max: Int = 5
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max, id: \.self) { index in
                Capsule()
                    .fill(index <= value ? tint : Color(.systemFill))
                    .frame(width: 14, height: 5)
            }
        }
        .accessibilityLabel("Rating \(value) of \(max)")
    }
}

// MARK: - Flow layout for chips

struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}

struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                // `.systemBackground` inverts correctly in both appearances
                // without assuming anything about the accent's luminance.
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemFill), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.2), value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Vector spool visualization

/// Clean vector rendering of a spool with the remaining filament wound
/// around it, tinted with the filament color. Not photorealistic.
struct SpoolRingView: View {
    let fraction: Double          // 0...1
    let filamentColor: Color
    var lineWidth: CGFloat = 16

    private var clampedFraction: Double { min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            // Hub
            Circle()
                .fill(Color(.tertiarySystemFill))
                .padding(lineWidth * 2.2)
            Circle()
                .fill(Color(.systemBackground))
                .padding(lineWidth * 2.2 + 10)
            // Empty spool flange (subtle)
            Circle()
                .stroke(Color(.systemGray4), lineWidth: lineWidth)
            // Wound filament
            Circle()
                .trim(from: 0, to: clampedFraction)
                .stroke(filamentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: clampedFraction)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Spool, \(Int(clampedFraction * 100)) percent filament remaining")
    }
}

// MARK: - Photo picker button storing Data

struct PhotoStripView: View {
    @Binding var photoDatas: [Data]
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: PK.Spacing.sm) {
            if !photoDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PK.Spacing.sm) {
                        ForEach(photoDatas.indices, id: \.self) { index in
                            if let image = UIImage(data: photoDatas[index]) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 72, height: 72)
                                    .clipShape(RoundedRectangle(cornerRadius: PK.Radius.chip))
                                    .contextMenu {
                                        Button("Remove", role: .destructive) {
                                            photoDatas.remove(at: index)
                                        }
                                    }
                            }
                        }
                    }
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Add Photo", systemImage: "photo.badge.plus")
                    .font(.subheadline)
            }
            .onChange(of: pickerItem) { _, newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        photoDatas.append(data)
                    }
                    pickerItem = nil
                }
            }
        }
    }
}
