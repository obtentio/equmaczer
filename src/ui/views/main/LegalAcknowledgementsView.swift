// equmaczer — Copyright (C) 2026 obtentio. Licensed under the GNU GPL v3 (see LICENSE).

import SwiftUI

/// The legal disclosure: the owner's copyright and the GPL-3.0 notice,
/// in a secondary view reached from the About pane. Upstream copyright
/// notices are preserved where the licence requires them — in the
/// source file headers and sbom/PROVENANCE.md, which accompany the
/// product (GPL-3.0 sections 0, 4 and 5).
struct LegalAcknowledgementsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingFullLicence = false

    private var licenceText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "The full text of the GNU General Public License v3 is in the LICENSE file at the root of the equmaczer source archive."
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("LEGAL")
                    .font(.eqT4)
                    .foregroundStyle(Color.eqG95)
                Spacer()
                Button("Close") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.eqT2Medium)
                    .foregroundStyle(Color.eqG80)
            }
            .padding(.bottom, 10)

            StructuralRule()
                .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("equmaczer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 3 of the Licence. equmaczer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG80)

                    Text("The corresponding source code for this version accompanies the product, as the Licence requires.")
                        .font(.eqT2)
                        .foregroundStyle(Color.eqG80)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Copyright © 2026 obtentio")
                    }
                    .font(.eqT2)
                    .foregroundStyle(Color.eqG60)

                    Button(showingFullLicence ? "HIDE THE FULL LICENCE" : "READ THE FULL LICENCE") {
                        showingFullLicence.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.eqT1)
                    .foregroundStyle(Color.eqG00)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.eqG95)
                    .clipShape(RoundedRectangle(cornerRadius: EQDesign.cornerControl))

                    if showingFullLicence {
                        Text(licenceText)
                            .font(.eqT0)
                            .foregroundStyle(Color.eqG80)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 520, height: 420)
        .background(Color.eqG05)
    }
}
