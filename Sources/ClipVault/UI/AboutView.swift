import MacUtilityKit
import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    MUKBrandIcon(symbol: "doc.on.clipboard", size: 52)
                    Text("ClipVault")
                        .font(.title3.weight(.semibold))
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your clipboard, searchable and private")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                MUKCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("© 2026 DeepDive Solna AB · MIT License")
                            .font(.callout.weight(.medium))
                        Text("Free and open source. ClipVault stores your clipboard history locally on this Mac; nothing is uploaded.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                MUKCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Acknowledgements")
                            .font(.subheadline.weight(.semibold))
                        ForEach(acknowledgements, id: \.name) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.caption.weight(.medium))
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private struct Acknowledgement {
        let name: String
        let detail: String
    }

    private var acknowledgements: [Acknowledgement] {
        [
            Acknowledgement(
                name: "SQLite",
                detail: "Embedded local database engine. Public domain."),
            Acknowledgement(
                name: "MacUtilityKit",
                detail: "Shared macOS UI toolkit by DeepDive Solna AB. MIT License.")
        ]
    }
}
