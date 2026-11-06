import SwiftUI

/// Column catalogue – drives the "Columns" menu and default visibility.
struct ColumnSpec: Identifiable {
    let id: String
    let title: String
    let defaultVisible: Bool
}

enum Columns {
    static let all: [ColumnSpec] = [
        ColumnSpec(id: "tags", title: "Tags", defaultVisible: true),
        ColumnSpec(id: "kind", title: "Kind", defaultVisible: true),
        ColumnSpec(id: "dimensions", title: "Dimensions", defaultVisible: true),
        ColumnSpec(id: "width", title: "Width", defaultVisible: false),
        ColumnSpec(id: "height", title: "Height", defaultVisible: false),
        ColumnSpec(id: "aspect", title: "Aspect Ratio", defaultVisible: false),
        ColumnSpec(id: "megapixels", title: "Megapixels", defaultVisible: false),
        ColumnSpec(id: "size", title: "Size", defaultVisible: true),
        ColumnSpec(id: "modified", title: "Date Modified", defaultVisible: true),
        ColumnSpec(id: "created", title: "Date Created", defaultVisible: false),
        ColumnSpec(id: "camera", title: "Camera", defaultVisible: true),
        ColumnSpec(id: "lens", title: "Lens", defaultVisible: false),
        ColumnSpec(id: "iso", title: "ISO", defaultVisible: false),
        ColumnSpec(id: "aperture", title: "Aperture", defaultVisible: false),
        ColumnSpec(id: "shutter", title: "Shutter", defaultVisible: false),
        ColumnSpec(id: "focal", title: "Focal Length", defaultVisible: false),
        ColumnSpec(id: "taken", title: "Date Taken", defaultVisible: true),
        ColumnSpec(id: "duration", title: "Duration", defaultVisible: true),
        ColumnSpec(id: "fps", title: "Frame Rate", defaultVisible: false),
        ColumnSpec(id: "codec", title: "Codec", defaultVisible: false),
        ColumnSpec(id: "color", title: "Color", defaultVisible: false),
        ColumnSpec(id: "dpi", title: "DPI", defaultVisible: false)
    ]

    static func spec(_ id: String) -> ColumnSpec? {
        all.first { $0.id == id }
    }
}

struct BrowserListView: View {
    @EnvironmentObject private var model: FolderModel
    let items: [FileItem]
    @Binding var sortOrder: [KeyPathComparator<FileItem>]
    @AppStorage("tableColumns") private var customization: TableColumnCustomization<FileItem>

    typealias Sort = KeyPathComparator<FileItem>

    var body: some View {
        Table(items, selection: $model.selection, sortOrder: $sortOrder, columnCustomization: $customization) {
            geometryColumns
            fileColumns
            cameraColumns
            videoColumns
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { ids in
            ItemContextMenu(model: model, ids: ids)
        } primaryAction: { ids in
            model.openSelection(ids)
        }
        .onKeyPress(.space) {
            model.toggleQuickLook()
            return .handled
        }
        .onKeyPress(.return) {
            guard model.selection.count == 1 else { return .ignored }
            model.beginRename(model.selection)
            return .handled
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ColumnsMenu(customization: $customization)
            }
        }
    }

    // MARK: Column groups (split up so the type-checker stays fast)

    @TableColumnBuilder<FileItem, Sort>
    private var geometryColumns: some TableColumnContent<FileItem, Sort> {
        nameColumn
        tagsColumn
        kindColumn
        dimensionsColumn
        widthColumn
        heightColumn
        aspectColumn
        megapixelsColumn
    }

    @TableColumnBuilder<FileItem, Sort>
    private var fileColumns: some TableColumnContent<FileItem, Sort> {
        sizeColumn
        modifiedColumn
        createdColumn
    }

    @TableColumnBuilder<FileItem, Sort>
    private var cameraColumns: some TableColumnContent<FileItem, Sort> {
        cameraColumn
        lensColumn
        isoColumn
        apertureColumn
        shutterColumn
        focalColumn
        takenColumn
    }

    @TableColumnBuilder<FileItem, Sort>
    private var videoColumns: some TableColumnContent<FileItem, Sort> {
        durationColumn
        fpsColumn
        codecColumn
        colorColumn
        dpiColumn
    }

    // MARK: Individual columns (explicitly typed)

    private var nameColumn: some TableColumnContent<FileItem, Sort> {
        let showThumbnail = model.showListThumbnails
        return TableColumn("Name", value: \FileItem.name, comparator: String.StandardComparator.localizedStandard) { (item: FileItem) in
            NameCell(item: item, showThumbnail: showThumbnail)
        }
        .width(min: 180, ideal: 280)
        .customizationID("name")
        .disabledCustomizationBehavior(.visibility)
    }

    private var tagsColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Tags", value: \FileItem.sortTags) { (item: FileItem) in TagsCell(item: item) }
            .width(min: 40, ideal: 70)
            .customizationID("tags")
    }

    private var kindColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Kind", value: \FileItem.kindLabel) { (item: FileItem) in Cell(item.kindLabel) }
            .width(min: 50, ideal: 70)
            .customizationID("kind")
    }

    private var dimensionsColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Dimensions", value: \FileItem.sortPixels) { (item: FileItem) in DimensionsCell(item: item) }
            .width(min: 100, ideal: 130)
            .customizationID("dimensions")
    }

    private var widthColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Width", value: \FileItem.sortWidth) { (item: FileItem) in Cell(item.widthText, numeric: true) }
            .width(min: 50, ideal: 70)
            .customizationID("width")
            .defaultVisibility(.hidden)
    }

    private var heightColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Height", value: \FileItem.sortHeight) { (item: FileItem) in Cell(item.heightText, numeric: true) }
            .width(min: 50, ideal: 70)
            .customizationID("height")
            .defaultVisibility(.hidden)
    }

    private var aspectColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Aspect", value: \FileItem.sortAspect) { (item: FileItem) in Cell(item.aspectText, numeric: true) }
            .width(min: 50, ideal: 70)
            .customizationID("aspect")
            .defaultVisibility(.hidden)
    }

    private var megapixelsColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("MP", value: \FileItem.sortMegapixels) { (item: FileItem) in Cell(item.megapixelsText, numeric: true) }
            .width(min: 50, ideal: 70)
            .customizationID("megapixels")
            .defaultVisibility(.hidden)
    }

    private var sizeColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Size", value: \FileItem.sortSize) { (item: FileItem) in Cell(item.sizeText, numeric: true) }
            .width(min: 60, ideal: 80)
            .customizationID("size")
    }

    private var modifiedColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Modified", value: \FileItem.modified) { (item: FileItem) in Cell(item.modifiedText) }
            .width(min: 110, ideal: 150)
            .customizationID("modified")
    }

    private var createdColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Created", value: \FileItem.sortCreated) { (item: FileItem) in Cell(item.createdText) }
            .width(min: 110, ideal: 150)
            .customizationID("created")
            .defaultVisibility(.hidden)
    }

    private var cameraColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Camera", value: \FileItem.sortCamera) { (item: FileItem) in Cell(item.cameraText) }
            .width(min: 100, ideal: 160)
            .customizationID("camera")
    }

    private var lensColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Lens", value: \FileItem.sortLens) { (item: FileItem) in Cell(item.sortLens) }
            .width(min: 100, ideal: 180)
            .customizationID("lens")
            .defaultVisibility(.hidden)
    }

    private var isoColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("ISO", value: \FileItem.sortISO) { (item: FileItem) in Cell(item.isoText, numeric: true) }
            .width(min: 55, ideal: 70)
            .customizationID("iso")
            .defaultVisibility(.hidden)
    }

    private var apertureColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Aperture", value: \FileItem.sortAperture) { (item: FileItem) in Cell(item.apertureText, numeric: true) }
            .width(min: 55, ideal: 70)
            .customizationID("aperture")
            .defaultVisibility(.hidden)
    }

    private var shutterColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Shutter", value: \FileItem.sortExposure) { (item: FileItem) in Cell(item.exposureText, numeric: true) }
            .width(min: 60, ideal: 75)
            .customizationID("shutter")
            .defaultVisibility(.hidden)
    }

    private var focalColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Focal", value: \FileItem.sortFocal) { (item: FileItem) in Cell(item.focalText, numeric: true) }
            .width(min: 55, ideal: 70)
            .customizationID("focal")
            .defaultVisibility(.hidden)
    }

    private var takenColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Taken", value: \FileItem.sortDateTaken) { (item: FileItem) in Cell(item.dateTakenText) }
            .width(min: 110, ideal: 150)
            .customizationID("taken")
    }

    private var durationColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Duration", value: \FileItem.sortDuration) { (item: FileItem) in Cell(item.durationText, numeric: true) }
            .width(min: 60, ideal: 75)
            .customizationID("duration")
    }

    private var fpsColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("FPS", value: \FileItem.sortFPS) { (item: FileItem) in Cell(item.fpsText, numeric: true) }
            .width(min: 55, ideal: 70)
            .customizationID("fps")
            .defaultVisibility(.hidden)
    }

    private var codecColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Codec", value: \FileItem.sortCodec) { (item: FileItem) in Cell(item.codecText) }
            .width(min: 60, ideal: 90)
            .customizationID("codec")
            .defaultVisibility(.hidden)
    }

    private var colorColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("Color", value: \FileItem.sortColor) { (item: FileItem) in Cell(item.colorText) }
            .width(min: 80, ideal: 130)
            .customizationID("color")
            .defaultVisibility(.hidden)
    }

    private var dpiColumn: some TableColumnContent<FileItem, Sort> {
        TableColumn("DPI", value: \FileItem.sortDPI) { (item: FileItem) in Cell(item.dpiText, numeric: true) }
            .width(min: 50, ideal: 65)
            .customizationID("dpi")
            .defaultVisibility(.hidden)
    }
}

// MARK: - Columns menu

struct ColumnsMenu: View {
    @Binding var customization: TableColumnCustomization<FileItem>

    private func isVisible(_ spec: ColumnSpec) -> Bool {
        switch customization[visibility: spec.id] {
        case .visible: return true
        case .hidden: return false
        default: return spec.defaultVisible
        }
    }

    var body: some View {
        Menu {
            ForEach(Columns.all) { spec in
                Toggle(spec.title, isOn: Binding(
                    get: { isVisible(spec) },
                    set: { customization[visibility: spec.id] = $0 ? .visible : .hidden }
                ))
            }
            Divider()
            Button("Show Camera Columns") {
                for id in ["camera", "lens", "iso", "aperture", "shutter", "focal", "taken"] {
                    customization[visibility: id] = .visible
                }
            }
            Button("Show Video Columns") {
                for id in ["duration", "fps", "codec"] {
                    customization[visibility: id] = .visible
                }
            }
            Button("Reset Columns") {
                customization = TableColumnCustomization()
            }
        } label: {
            Label("Columns", systemImage: "slider.horizontal.3")
        }
        .help("Choose which columns to show")
    }
}

// MARK: - Cells

private struct NameCell: View {
    let item: FileItem
    let showThumbnail: Bool

    var body: some View {
        HStack(spacing: 8) {
            ThumbnailView(item: item, size: 22, cornerRadius: 3, allowThumbnail: showThumbnail)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            if item.isShortlisted {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.yellow)
                    .help("Shortlisted")
            }
        }
        .help(item.url.path)
    }
}

/// Star + Finder colour dots, like Finder's Tags column.
struct TagsCell: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 3) {
            if item.isShortlisted {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.yellow)
            }
            ForEach(item.colorTags) { tag in
                TagDot(tag: tag, size: 10)
            }
            if !item.customTags.isEmpty {
                Text(item.customTags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if item.tags.isEmpty {
                Text("—").foregroundStyle(.quaternary)
            }
        }
        .help(item.tags.isEmpty ? "No tags" : item.tags.joined(separator: ", "))
    }
}

private struct Cell: View {
    let text: String
    var numeric = false

    init(_ text: String, numeric: Bool = false) {
        self.text = text
        self.numeric = numeric
    }

    var body: some View {
        if text.isEmpty {
            Text("—").foregroundStyle(.quaternary)
        } else if numeric {
            Text(text).monospacedDigit().lineLimit(1)
        } else {
            Text(text).lineLimit(1).truncationMode(.tail)
        }
    }
}

private struct DimensionsCell: View {
    let item: FileItem

    var body: some View {
        if item.dimensionsText.isEmpty {
            if item.metaState == .pending {
                Text("…").foregroundStyle(.quaternary)
            } else {
                Text("—").foregroundStyle(.quaternary)
            }
        } else {
            Text(item.dimensionsText)
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(item.hasDimensions ? Color.primary : Color.secondary)
        }
    }
}

// MARK: - Context menu (shared by list and grid)

struct ItemContextMenu: View {
    @ObservedObject var model: FolderModel
    let ids: Set<FileItem.ID>

    private var single: FileItem? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.item(for: id)
    }

    private var plural: Bool { ids.count > 1 }

    var body: some View {
        if ids.isEmpty {
            Button("New Folder") { model.newFolder() }
            Button("Paste") { model.pasteFromClipboard(move: false) }
                .disabled(!model.canPaste)
            Button("Move Items Here") { model.pasteFromClipboard(move: true) }
                .disabled(!model.canPaste)
            Divider()
            Button("Refresh") { model.refresh() }
            Button("Open Folder…") { model.chooseFolder() }
        } else {
            Group {
                Button(single?.kind == .folder ? "Open Folder" : "Open") { model.openSelection(ids) }
                if let single, single.kind != .folder {
                    Button("Quick Look") { model.showQuickLook(single) }
                }
                Button("Reveal in Finder") { model.revealInFinder(ids) }
                if single != nil {
                    Button("Rename…") { model.beginRename(ids) }
                }
                Divider()
                TagMenuItems(model: model, ids: ids)
                Divider()
            }
            Group {
                Button(plural ? "Copy \(ids.count) Items" : "Copy") { model.copyToClipboard(ids) }
                Button("Paste") { model.pasteFromClipboard(move: false) }
                    .disabled(!model.canPaste)
                Button("Duplicate") { model.duplicate(ids) }
                Divider()
                Button("Copy to Folder…") { model.transferToChosenFolder(ids, move: false) }
                Button("Move to Folder…") { model.transferToChosenFolder(ids, move: true) }
                Button(plural ? "New Folder with Selection" : "New Folder with Item") { model.newFolderWithSelection(ids) }
                Divider()
            }
            Group {
                Button("Copy Dimensions") { model.copyDimensions(ids) }
                    .disabled(!ids.contains { model.item(for: $0)?.hasDimensions == true })
                Button(plural ? "Copy Names" : "Copy Name") { model.copyNames(ids) }
                Button(plural ? "Copy Paths" : "Copy Path") { model.copyPaths(ids) }
                Divider()
                Button("Show in Inspector") {
                    if let id = ids.first, ids.count == 1 { model.selection = [id] }
                    model.showInspector = true
                }
                Divider()
            }
            Button("Move to Trash", role: .destructive) { model.moveToTrash(ids) }
        }
    }
}


/// Shortlist toggle + colour tag submenu, shared by the context menu and the Edit menu.
struct TagMenuItems: View {
    @ObservedObject var model: FolderModel
    let ids: Set<FileItem.ID>

    private var allShortlisted: Bool {
        let chosen = ids.compactMap { model.item(for: $0) }
        return !chosen.isEmpty && chosen.allSatisfy(\.isShortlisted)
    }

    var body: some View {
        Button {
            model.toggleShortlist(ids)
        } label: {
            Label(allShortlisted ? "Remove from Shortlist" : "Add to Shortlist", systemImage: allShortlisted ? "star.slash" : "star")
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
        .disabled(ids.isEmpty)
        Menu("Tags") {
            ForEach(Array(FinderTag.allCases.enumerated()), id: \.element) { index, tag in
                let on = !ids.isEmpty && ids.allSatisfy { model.item(for: $0)?.colorTags.contains(tag) == true }
                Toggle(isOn: Binding(get: { on }, set: { _ in model.toggleTag(tag, for: ids) })) {
                    Label { Text(tag.rawValue) } icon: { Image(nsImage: TagDot.image(for: tag)) }
                }
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .control)
            }
            Divider()
            Button("Remove All Tags") { model.clearTags(ids) }
                .keyboardShortcut("0", modifiers: .control)
        }
        .disabled(ids.isEmpty)
    }
}
