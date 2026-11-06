import SwiftUI

struct BrowserGridView: View {
    @EnvironmentObject private var model: FolderModel
    let items: [FileItem]

    private var cellSize: CGFloat { CGFloat(model.gridThumbSize) }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                ForEach(items) { item in
                    cell(for: item)
                }
            }
            .padding(16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .contextMenu {
            ItemContextMenu(model: model, ids: [])
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            model.toggleQuickLook()
            return .handled
        }
        .onKeyPress(.return) {
            guard model.selection.count == 1 else { return .ignored }
            model.beginRename(model.selection)
            return .handled
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: cellSize + 20, maximum: cellSize + 60), spacing: 10)]
    }

    private func menuIDs(for item: FileItem) -> Set<FileItem.ID> {
        model.selection.contains(item.id) ? model.selection : [item.id]
    }

    private func cell(for item: FileItem) -> some View {
        GridCell(item: item, size: cellSize, selected: model.selection.contains(item.id))
            .onAppear { if item.metaState == .pending { model.requestMetadata(item.id) } }
            .onTapGesture(count: 2) {
                model.openItem(item)
            }
            .onTapGesture {
                let flags = NSEvent.modifierFlags
                let extend = flags.contains(.command) || flags.contains(.shift)
                model.select(item.id, extend: extend)
            }
            .contextMenu {
                ItemContextMenu(model: model, ids: menuIDs(for: item))
            }
    }
}

private struct GridCell: View {
    let item: FileItem
    let size: CGFloat
    let selected: Bool

    private var caption: String {
        var parts: [String] = []
        if !item.dimensionsText.isEmpty { parts.append(item.dimensionsText) }
        if item.kind == .video, !item.durationText.isEmpty { parts.append(item.durationText) }
        if item.kind != .folder, !item.sizeText.isEmpty { parts.append(item.sizeText) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
                ThumbnailView(item: item, size: size - 12, cornerRadius: 4)
            }
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                if item.isShortlisted {
                    Image(systemName: "star.fill")
                        .font(.system(size: max(9, size * 0.1)))
                        .foregroundStyle(Color.yellow)
                        .padding(4)
                        .background(Color.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if item.kind == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: max(8, size * 0.09)))
                        .padding(5)
                        .background(Color.black.opacity(0.55), in: Circle())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
            )

            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    ForEach(item.colorTags.prefix(3)) { tag in
                        TagDot(tag: tag, size: 8)
                    }
                    Text(item.name)
                        .font(.callout)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.accentColor : .clear)
                )
                .foregroundStyle(selected ? Color.white : Color.primary)
                Text(caption.isEmpty ? (item.metaState == .pending ? "…" : " ") : caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: size + 16)
        }
        .padding(6)
        .contentShape(Rectangle())
        .help(item.url.path)
    }
}
