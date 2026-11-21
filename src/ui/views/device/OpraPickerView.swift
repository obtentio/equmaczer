// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).
import SwiftUI

/// The OPRA catalog picker (A7): search products, see every preset
/// published for one — each with its author and the source's own
/// details (rig and target) — and choose. Disagreement between
/// presets is shown, not hidden: two corrections for the same
/// headphone sit side by side with their origins named, and the
/// listener picks.
///
/// Attribution (OPRA data is CC BY-SA 4.0): the preset author's
/// name leads every preset row; OPRA is credited in the footer.
struct OpraPickerView: View {
    let catalog: OpraCatalog
    let onSelect: (OpraProduct, OpraPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private static let maxRenderedProducts = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose a correction")
                .font(.headline)

            TextField("Search headphones", text: $query)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(renderedProducts, id: \.id) { product in
                    Section {
                        ForEach(Array(product.presets.enumerated()), id: \.offset) { _, preset in
                            Button {
                                onSelect(product, preset)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.author)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    if let details = preset.details {
                                        Text(details)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("\(preset.bands.count) bands · preamp \(preset.preampDB, specifier: "%.1f") dB")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(product.vendorName.map { "\($0) \(product.name)" } ?? product.name)
                    }
                }
            }
            .listStyle(.inset)

            if filteredProducts.count > Self.maxRenderedProducts {
                Text("Showing the first \(Self.maxRenderedProducts) of \(filteredProducts.count) matches — keep typing to narrow the search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Presets from OPRA, the open headphone EQ database (CC BY-SA 4.0) — github.com/opra-project/opra. Each preset belongs to its author, credited above.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 460, height: 520)
    }

    private var filteredProducts: [OpraProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return catalog.products }
        return catalog.products.filter { product in
            product.name.localizedCaseInsensitiveContains(trimmed)
                || (product.vendorName?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    private var renderedProducts: [OpraProduct] {
        Array(filteredProducts.prefix(Self.maxRenderedProducts))
    }
}
