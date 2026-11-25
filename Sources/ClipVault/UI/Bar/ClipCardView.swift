import AppKit
import ImageIO
import MacUtilityKit
import SwiftUI

enum CardMetrics {
    static let width: CGFloat = 230
    static let height: CGFloat = 230
    static let headerHeight: CGFloat = 44
}

/// Thumbnails, pixel sizes and app icons for cards, loaded off the main thread and cached.
@MainActor
final class CardImageCache: ObservableObject {
    @Published private(set) var thumbnails: [String: NSImage] = [:]
    private(set) var pixelSizes: [String: CGSize] = [:]
    private var requested: Set<String> = []
    private var icons: [String: NSImage] = [:]
    var store: ClipStore?

    func thumbnail(for item: ClipboardItem) -> NSImage? {
        if let image = thumbnails[item.id] { return image }
        guard item.kind == .image, !requested.contains(item.id), let store else { return nil }
        requested.insert(item.id)
        Task { [weak self] in
            guard let items = try? await store.payloadItems(for: item),
                  let data = items.lazy.flatMap({ $0 }).first(where: { ClipboardClassifier.imageTypes.contains($0.type) })?.data
            else { return }
            let result = await Task.detached { Self.downsample(data) }.value
            guard let self, let (image, size) = result else { return }
            self.pixelSizes[item.id] = size
            self.thumbnails[item.id] = image
        }
        return nil
    }

    func forget(_ id: String) {
        thumbnails[id] = nil
        requested.remove(id)
    }

    nonisolated private static func downsample(_ data: Data) -> (NSImage, CGSize)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        var size = CGSize.zero
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let w = props[kCGImagePropertyPixelWidth] as? CGFloat, let h = props[kCGImagePropertyPixelHeight] as? CGFloat {
            size = CGSize(width: w, height: h)
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 600,
                                        kCGImageSourceCreateThumbnailWithTransform: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return (NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), size)
    }

    func appIcon(bundleID: String?) -> NSImage? {
        guard let bundleID else { return nil }
        if let icon = icons[bundleID] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    func appName(bundleID: String?) -> String? {
        guard let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    /// A stable colour per source app.
    static func color(for bundleID: String?) -> Color {
        guard let bundleID else { return Color.gray }
        var hash: UInt64 = 1469598103934665603
        for byte in bundleID.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.55, brightness: 0.72)
    }
}

struct ClipCardView: View {
    let item: ClipboardItem
    @ObservedObject var images: CardImageCache
    let isCursor: Bool
    let isSelected: Bool
    /// 1–9 when the card can be quick-pasted with ⌘n.
    let quickIndex: Int?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footer
        }
        .frame(width: CardMetrics.width, height: CardMetrics.height)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: MUKTheme.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: MUKTheme.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? MUKTheme.accent : Color.primary.opacity(0.08), lineWidth: isSelected ? 3 : 1))
        .shadow(color: .black.opacity(isCursor ? 0.3 : 0.12), radius: isCursor ? 8 : 3, y: 2)
        .scaleEffect(isCursor ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: isCursor)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? kindLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(Self.relativeFormatter.localizedString(for: item.lastCopiedAt, relativeTo: Date()))
                    .font(.system(size: 11))
                    .opacity(0.85)
            }
            Spacer(minLength: 0)
            if let icon = images.appIcon(bundleID: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 28, height: 28)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: CardMetrics.headerHeight)
        .background(CardImageCache.color(for: item.sourceBundleID))
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .text:
            Text(item.preview)
                .font(.system(size: 12))
                .lineLimit(10)
                .padding(10)
        case .link:
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "link").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(URL(string: item.preview)?.host ?? "").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(item.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(5)
            }
            .padding(10)
        case .color:
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 8).fill(Self.swatch(item.preview)).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(item.preview.uppercased()).font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .padding(10)
        case .image:
            if let image = images.thumbnail(for: item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(6)
            } else {
                Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .files:
            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc").font(.system(size: 22)).foregroundStyle(.secondary)
                Text(item.preview).font(.system(size: 12)).lineLimit(3)
            }
            .padding(10)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerText).lineLimit(1)
            Spacer()
            if item.pinned { Image(systemName: "pin.fill") }
            if let quickIndex { Text("⌘\(quickIndex)").monospacedDigit() }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var kindLabel: String {
        switch item.kind {
        case .text: return "Text"
        case .link: return "Link"
        case .color: return "Colour"
        case .image: return "Image"
        case .files: return item.preview.hasSuffix(" files") ? "Files" : "File"
        }
    }

    private var footerText: String {
        switch item.kind {
        case .text, .link, .color, .files: return images.appName(bundleID: item.sourceBundleID) ?? ""
        case .image:
            if let size = images.pixelSizes[item.id], size != .zero { return "\(Int(size.width)) × \(Int(size.height))" }
            return ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file)
        }
    }

    static func swatch(_ hex: String) -> Color {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let value = UInt32(digits, radix: 16) ?? 0
        return Color(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255,
                     blue: Double(value & 0xff) / 255)
    }
}
