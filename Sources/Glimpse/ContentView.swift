import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: FolderModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            BrowserView()
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 260, ideal: 310, max: 460)
        }
        .toolbar { toolbarContent }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "Filter by name")
        .navigationTitle(model.currentURL?.lastPathComponent ?? "Glimpse")
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                model.open(url)
            } else {
                model.open(url.deletingLastPathComponent())
                model.selection = [url.standardizedFileURL.path]
            }
            return true
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                .disabled(!model.canGoBack)
                .help("Back")
            Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                .disabled(!model.canGoForward)
                .help("Forward")
            Button { model.goUp() } label: { Image(systemName: "arrow.up.to.line") }
                .disabled(!model.canGoUp)
                .help("Enclosing folder (⌘↑)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: $model.viewMode) {
                Image(systemName: "list.bullet").tag(ViewMode.list).help("List (⌘1)")
                Image(systemName: "square.grid.2x2").tag(ViewMode.grid).help("Thumbnails (⌘2)")
            }
            .pickerStyle(.segmented)
            .help("View mode")

            Picker("Show", selection: $model.typeFilter) {
                ForEach(TypeFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .help("Which kinds of items to show")

            TagFilterMenu()

            Button { model.newFolder() } label: { Image(systemName: "folder.badge.plus") }
                .help("New folder (⇧⌘N)")

            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Re-read this folder (⌘R)")

            Button { model.showInspector.toggle() } label: { Image(systemName: "sidebar.trailing") }
                .help("Show or hide the inspector (⌥⌘I)")
        }
    }
}

/// Toolbar menu to narrow the listing to shortlisted / colour-tagged items.
struct TagFilterMenu: View {
    @EnvironmentObject private var model: FolderModel

    private var options: [TagFilter] {
        [.any, .shortlist] + FinderTag.allCases.map { TagFilter.color($0) } + [.untagged]
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { model.tagFilter == option },
                    set: { _ in model.tagFilter = option }
                )) {
                    switch option {
                    case .shortlist:
                        Label(option.label, systemImage: "star.fill")
                    case .color(let tag):
                        Label { Text(option.label) } icon: { Image(nsImage: TagDot.image(for: tag)) }
                    default:
                        Text(option.label)
                    }
                }
            }
        } label: {
            Label("Tags", systemImage: model.tagFilter == .any ? "tag" : "tag.fill")
        }
        .help("Show only shortlisted or tagged items")
    }
}

/// A Finder-coloured dot, as a view and as a menu-safe NSImage.
struct TagDot: View {
    let tag: FinderTag
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(TagDot.color(for: tag))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.15), lineWidth: 0.5))
            .frame(width: size, height: size)
    }

    static func color(for tag: FinderTag) -> Color {
        Color(red: tag.rgb.0, green: tag.rgb.1, blue: tag.rgb.2)
    }

    private static var imageCache: [FinderTag: NSImage] = [:]

    /// Menus flatten custom views, so colour swatches in menus are real NSImages.
    static func image(for tag: FinderTag) -> NSImage {
        if let cached = imageCache[tag] { return cached }
        let size = NSSize(width: 14, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            let dot = rect.insetBy(dx: 2, dy: 2)
            NSColor(red: tag.rgb.0, green: tag.rgb.1, blue: tag.rgb.2, alpha: 1).setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            NSBezierPath(ovalIn: dot).stroke()
            return true
        }
        image.isTemplate = false
        imageCache[tag] = image
        return image
    }
}
