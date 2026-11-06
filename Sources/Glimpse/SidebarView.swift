import SwiftUI

struct SidebarPlace: Identifiable {
    let url: URL
    let name: String
    let symbol: String
    var id: String { url.path }
}

/// A row in the sidebar. The same folder can appear in several sections
/// (Places, Favorites, Recent), so rows are identified by section + path and
/// only the row the user clicked is highlighted.
struct SidebarEntry: Hashable {
    let section: String
    let path: String

    var url: URL { URL(fileURLWithPath: path) }
}

struct SidebarView: View {
    @EnvironmentObject private var model: FolderModel
    @State private var clicked: SidebarEntry?

    private var allEntries: [SidebarEntry] {
        Self.places.map { SidebarEntry(section: "places", path: $0.url.path) }
            + model.favorites.map { SidebarEntry(section: "favorites", path: $0.path) }
            + Self.volumes.map { SidebarEntry(section: "volumes", path: $0.url.path) }
            + model.recents.map { SidebarEntry(section: "recents", path: $0.path) }
    }

    /// Highlight the clicked row while it still matches the current folder,
    /// otherwise the first row that points at the current folder.
    private var selectionBinding: Binding<SidebarEntry?> {
        Binding(
            get: {
                guard let current = model.currentURL?.path else { return nil }
                if let clicked, clicked.path == current { return clicked }
                return allEntries.first { $0.path == current }
            },
            set: { entry in
                clicked = entry
                if let entry { model.open(entry.url) }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            sidebarList
            Divider()
            Button {
                model.chooseFolder()
            } label: {
                Label("Open Folder…", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private var sidebarList: some View {
        List(selection: selectionBinding) {
            Section("Places") {
                ForEach(Self.places) { place in
                    Label(place.name, systemImage: place.symbol)
                        .tag(SidebarEntry(section: "places", path: place.url.path))
                }
            }

            if !model.favorites.isEmpty {
                Section("Favorites") {
                    ForEach(model.favorites, id: \.path) { url in
                        Label(url.lastPathComponent, systemImage: "star")
                            .tag(SidebarEntry(section: "favorites", path: url.path))
                            .help(url.path)
                            .contextMenu {
                                Button("Remove from Favorites") { model.removeFavorite(url) }
                                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                            }
                    }
                }
            }

            Section("Volumes") {
                ForEach(Self.volumes) { volume in
                    Label(volume.name, systemImage: volume.symbol)
                        .tag(SidebarEntry(section: "volumes", path: volume.url.path))
                }
            }

            if !model.recents.isEmpty {
                Section {
                    ForEach(model.recents, id: \.path) { url in
                        Label(url.lastPathComponent, systemImage: "clock")
                            .tag(SidebarEntry(section: "recents", path: url.path))
                            .help(url.path)
                    }
                } header: {
                    HStack {
                        Text("Recent")
                        Spacer()
                        Button("Clear") { model.clearRecents() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 10)
                            .help("Forget the recent folders")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: Static data

    static let places: [SidebarPlace] = {
        let fm = FileManager.default
        var list: [SidebarPlace] = []
        func add(_ dir: FileManager.SearchPathDirectory, _ name: String, _ symbol: String) {
            if let url = fm.urls(for: dir, in: .userDomainMask).first, fm.fileExists(atPath: url.path) {
                list.append(SidebarPlace(url: url.standardizedFileURL, name: name, symbol: symbol))
            }
        }
        add(.desktopDirectory, "Desktop", "menubar.dock.rectangle")
        add(.documentDirectory, "Documents", "doc.text")
        add(.downloadsDirectory, "Downloads", "arrow.down.circle")
        add(.picturesDirectory, "Pictures", "photo.on.rectangle")
        add(.moviesDirectory, "Movies", "film")
        list.append(SidebarPlace(url: fm.homeDirectoryForCurrentUser.standardizedFileURL, name: "Home", symbol: "house"))
        return list
    }()

    static var volumes: [SidebarPlace] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey, .volumeIsRemovableKey]
        let urls = fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            let name = values?.volumeName ?? url.lastPathComponent
            let symbol = (values?.volumeIsRemovable == true) ? "externaldrive" : "internaldrive"
            return SidebarPlace(url: url.standardizedFileURL, name: name, symbol: symbol)
        }
    }
}
