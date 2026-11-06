import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct BrowserView: View {
    @EnvironmentObject private var model: FolderModel
    @State private var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\FileItem.name, comparator: String.StandardComparator.localizedStandard)
    ]

    /// Filtered + sorted, folders always listed first (like Finder with "Keep folders on top").
    private var displayedItems: [FileItem] {
        let filtered = model.filteredItems
        let folders = filtered.filter { $0.kind == .folder }.sorted(using: sortOrder)
        let files = filtered.filter { $0.kind != .folder }.sorted(using: sortOrder)
        return folders + files
    }

    var body: some View {
        VStack(spacing: 0) {
            PathBar()
            Divider()
            Group {
                if model.items.isEmpty && !model.isScanning {
                    emptyState
                } else if model.viewMode == .list {
                    BrowserListView(items: displayedItems, sortOrder: $sortOrder)
                } else {
                    BrowserGridView(items: displayedItems)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .quickLookPreview($model.quickLookURL, in: quickLookItems)
            .onChange(of: model.quickLookURL) { _, url in
                // Arrow keys inside the Quick Look panel move through the folder; keep the selection in sync.
                if let url, let item = model.item(for: url.standardizedFileURL.path), !model.selection.contains(item.id) {
                    model.selection = [item.id]
                }
            }
            Divider()
            StatusBar()
        }
        .onDeleteCommand { model.moveToTrash(model.selection) }
        .onCopyCommand { copyProviders() }
        .onPasteCommand(of: [.fileURL]) { _ in model.pasteFromClipboard(move: false) }
        .alert("Rename", isPresented: Binding(
            get: { model.renameTarget != nil },
            set: { if !$0 { model.renameTarget = nil } }
        )) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { model.commitRename() }
            Button("Cancel", role: .cancel) { model.renameTarget = nil }
        } message: {
            Text("Enter a new name for \u{201C}\(model.renameTarget?.name ?? "")\u{201D}.")
        }
    }

    private var quickLookItems: [URL] {
        displayedItems.filter { $0.kind != .folder }.map(\.url)
    }

    private func copyProviders() -> [NSItemProvider] {
        model.copyToClipboard(model.selection)
        return model.selection.compactMap { id in
            model.item(for: id).map { NSItemProvider(object: $0.url as NSURL) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("This folder is empty")
                .font(.title3)
                .foregroundStyle(.secondary)
            if !model.showHidden {
                Text("Hidden files are not shown (⇧⌘.)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Path bar

struct PathBar: View {
    @EnvironmentObject private var model: FolderModel

    private var crumbs: [(name: String, url: URL)] {
        guard let current = model.currentURL else { return [] }
        let components = current.pathComponents
        var result: [(String, URL)] = []
        var url = URL(fileURLWithPath: "/")
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        for (index, component) in components.enumerated() {
            if index == 0 {
                result.append(("Macintosh HD", url))
                continue
            }
            url = url.appendingPathComponent(component)
            if url.path == home {
                result = [("Home", url)]
            } else {
                result.append((component, url))
            }
        }
        return result.map { (name: $0.0, url: $0.1) }
    }

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        Button {
                            model.open(crumb.url)
                        } label: {
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Image(systemName: crumb.name == "Home" ? "house.fill" : "internaldrive.fill")
                                        .font(.system(size: 10))
                                }
                                Text(crumb.name)
                                    .lineLimit(1)
                            }
                            .font(.callout)
                            .fontWeight(index == crumbs.count - 1 ? .semibold : .regular)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(index == crumbs.count - 1 ? Color.primary.opacity(0.07) : .clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .help(crumb.url.path)
                    }
                }
                .padding(.horizontal, 10)
            }
            Spacer(minLength: 0)
            if let url = model.currentURL {
                Button {
                    model.toggleFavorite(url)
                } label: {
                    Image(systemName: model.isFavorite(url) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavorite(url) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(model.isFavorite(url) ? "Remove from Favorites" : "Add to Favorites (⌘D)")
                .padding(.trailing, 10)
            }
        }
        .frame(height: 30)
        .background(.bar)
    }
}

// MARK: - Status bar

struct StatusBar: View {
    @EnvironmentObject private var model: FolderModel

    var body: some View {
        HStack(spacing: 12) {
            Text(model.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
                Text("Working…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.isScanning {
                ProgressView()
                    .controlSize(.small)
                Text("Reading \(model.loadedCount) of \(model.items.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            if model.viewMode == .grid {
                Image(systemName: "photo")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Slider(value: $model.gridThumbSize, in: 64...320, step: 16)
                    .frame(width: 140)
                    .controlSize(.small)
                Image(systemName: "photo")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.bar)
    }
}
