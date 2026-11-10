import AppKit
import MacUtilityKit
import SwiftUI

struct HistoryRowView: View {
    let item: ClipboardItem
    let thumbnail: NSImage?
    let isSelected: Bool
    let shortcutIndex: Int?
    let restore: () -> Void
    let togglePin: () -> Void
    let delete: () -> Void

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(spacing: 10) {
            kindPreview

            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview.isEmpty ? "(empty)" : item.preview)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    if let appName = sourceAppName {
                        Text(appName)
                        Text("·")
                    }
                    Text(Self.relativeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            }

            Spacer(minLength: 0)

            if let shortcutIndex, isSelected {
                Text("⌘\(shortcutIndex)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }

            if item.pinned || isSelected {
                Button(action: togglePin) {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.pinned ? AnyShapeStyle(MUKTheme.accent) : AnyShapeStyle(.secondary))
                }
                .buttonStyle(.borderless)
                .help(item.pinned ? "Unpin" : "Pin")
            }

            if isSelected {
                Button(action: delete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selectionBackground)
        .contentShape(Rectangle())
        .onTapGesture(perform: restore)
    }

    @ViewBuilder private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: MUKTheme.rowRadius, style: .continuous)
                .fill(MUKTheme.accent.opacity(0.14))
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MUKTheme.accent)
                        .frame(width: 3)
                        .padding(.vertical, 4)
                }
        }
    }

    @ViewBuilder private var kindPreview: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .controlBackgroundColor))
                Image(systemName: iconName)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 36, height: 36)
        }
    }

    private var iconName: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }

    private var sourceAppName: String? {
        guard let bundleID = item.sourceBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
