import SwiftUI

/// Lazily loads a thumbnail for an item; cancels when scrolled away.
/// With `allowThumbnail == false` it shows the Finder file icon instantly instead.
struct ThumbnailView: View {
    let item: FileItem
    let size: CGFloat
    var cornerRadius: CGFloat = 4
    var allowThumbnail: Bool = true

    @State private var image: NSImage?

    private var wantsThumbnail: Bool {
        allowThumbnail && (item.kind == .image || item.kind == .video || item.kind == .pdf)
    }

    var body: some View {
        ZStack {
            if wantsThumbnail {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(size > 48 ? .high : .medium)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                        .overlay {
                            Image(systemName: item.kind.symbol)
                                .font(.system(size: max(9, size * 0.35)))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(size > 48 ? size * 0.15 : 0)
                }
            } else {
                Image(nsImage: ThumbnailLoader.shared.icon(for: item))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .task(id: taskKey) {
            guard wantsThumbnail else { return }
            image = await ThumbnailLoader.shared.thumbnail(for: item, size: size)
        }
    }

    private var taskKey: String {
        "\(item.id)#\(Int(size))#\(Int(item.modified.timeIntervalSince1970))#\(allowThumbnail)"
    }
}
