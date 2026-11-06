import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var model: FolderModel

    var body: some View {
        Group {
            if let item = model.selectedItem {
                SingleItemInspector(item: item)
            } else if model.selection.count > 1 {
                MultiSelectionInspector(items: model.selectedItems)
            } else {
                FolderSummaryInspector()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Single item

private struct SingleItemInspector: View {
    @EnvironmentObject private var model: FolderModel
    let item: FileItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                    ThumbnailView(item: item, size: 232, cornerRadius: 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 248)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.headline)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Text(headline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                if item.hasDimensions {
                    HStack(spacing: 8) {
                        Button {
                            model.copyToPasteboard(item.dimensionsText)
                        } label: {
                            Label("Copy Size", systemImage: "doc.on.doc")
                        }
                        Button {
                            model.copyToPasteboard("width: \(item.widthText)px; height: \(item.heightText)px;")
                        } label: {
                            Label("Copy CSS", systemImage: "curlybraces")
                        }
                        .help("Copies width/height as CSS")
                    }
                    .controlSize(.small)
                }

                TagEditor(item: item)

                InspectorSection(title: "General", rows: generalRows)

                if item.kind == .image || item.kind == .video || item.kind == .pdf {
                    InspectorSection(title: item.kind == .pdf ? "Document" : "Media", rows: mediaRows)
                }
                if !cameraRows.isEmpty {
                    InspectorSection(title: "Camera", rows: cameraRows)
                }
                if let error = item.meta?.error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                HStack(spacing: 8) {
                    if item.kind != .folder {
                        Button("Quick Look") { model.showQuickLook(item) }
                    }
                    Button("Open") { model.openItem(item) }
                    Button("Reveal in Finder") { model.revealInFinder([item.id]) }
                }
                .controlSize(.small)
            }
            .padding(14)
        }
    }

    private var headline: String {
        var parts: [String] = []
        if let type = item.contentType?.localizedDescription, !type.isEmpty {
            parts.append(type)
        } else {
            parts.append(item.kind.label)
        }
        if !item.sizeText.isEmpty { parts.append(item.sizeText) }
        return parts.joined(separator: " · ")
    }

    private var generalRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("Kind", item.kindLabel))
        if item.kind == .folder {
            if let n = item.meta?.itemCount { rows.append(("Contains", n == 1 ? "1 item" : "\(n) items")) }
            if let s = item.meta?.folderSize { rows.append(("Size", Formatters.bytes(s))) }
            else if !model.computeFolderSizes { rows.append(("Size", "Enable “Calculate Folder Sizes” in View menu")) }
        } else {
            rows.append(("Size", Formatters.bytes(item.fileSize)))
        }
        rows.append(("Modified", item.modifiedText))
        if !item.createdText.isEmpty { rows.append(("Created", item.createdText)) }
        rows.append(("Where", item.url.deletingLastPathComponent().path))
        return rows
    }

    private var mediaRows: [(String, String)] {
        guard let meta = item.meta else { return [("Status", "Reading…")] }
        var rows: [(String, String)] = []
        if item.hasDimensions {
            rows.append(("Dimensions", item.dimensionsText + " px"))
            rows.append(("Aspect ratio", item.aspectText))
            if !item.megapixelsText.isEmpty { rows.append(("Megapixels", item.megapixelsText)) }
            if let o = meta.orientation, (5...8).contains(o) {
                rows.append(("Orientation", "Rotated (EXIF \(o))"))
            }
        }
        if let s = meta.pageSize {
            rows.append(("Page size", "\(Int(s.width.rounded())) × \(Int(s.height.rounded())) pt"))
            let inches = String(format: "%.2f × %.2f in", s.width / 72, s.height / 72)
            rows.append(("", inches))
        }
        if let n = meta.pageCount { rows.append(("Pages", "\(n)")) }
        if let n = meta.frameCount { rows.append(("Frames", "\(n)")) }
        if !item.dpiText.isEmpty { rows.append(("Resolution", item.dpiText)) }
        if !item.colorText.isEmpty { rows.append(("Color", item.colorText)) }
        if let p = meta.profile { rows.append(("Profile", p)) }
        if !item.durationText.isEmpty { rows.append(("Duration", item.durationText)) }
        if !item.fpsText.isEmpty { rows.append(("Frame rate", item.fpsText)) }
        if let c = meta.codec { rows.append(("Video codec", c)) }
        if !item.bitrateText.isEmpty { rows.append(("Bit rate", item.bitrateText)) }
        if let a = meta.audioCodec {
            var audio = a
            if let rate = meta.sampleRate, rate > 0 { audio += String(format: " · %.1f kHz", rate / 1000) }
            if let ch = meta.channels { audio += ch == 1 ? " · Mono" : ch == 2 ? " · Stereo" : " · \(ch) ch" }
            rows.append(("Audio", audio))
        }
        return rows
    }

    private var cameraRows: [(String, String)] {
        guard let meta = item.meta else { return [] }
        var rows: [(String, String)] = []
        if !item.cameraText.isEmpty { rows.append(("Camera", item.cameraText)) }
        if let lens = meta.lens { rows.append(("Lens", lens)) }
        if let f = meta.focalLength {
            var text = Formatters.millimetres(f)
            if let eq = meta.focalLength35, Double(eq) != f { text += " (\(eq) mm equiv.)" }
            rows.append(("Focal length", text))
        }
        if !item.apertureText.isEmpty { rows.append(("Aperture", item.apertureText)) }
        if !item.exposureText.isEmpty { rows.append(("Shutter", item.exposureText)) }
        if !item.isoText.isEmpty { rows.append(("ISO", item.isoText)) }
        if !item.dateTakenText.isEmpty { rows.append(("Taken", item.dateTakenText)) }
        if let gps = meta.gps { rows.append(("Location", gps.text)) }
        if let sw = meta.software { rows.append(("Software", sw)) }
        return rows
    }
}

// MARK: - Tag editor

private struct TagEditor: View {
    @EnvironmentObject private var model: FolderModel
    let item: FileItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SHORTLIST & TAGS")
                .kerning(0.5)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button {
                    model.toggleShortlist([item.id])
                } label: {
                    Label(item.isShortlisted ? "Shortlisted" : "Shortlist", systemImage: item.isShortlisted ? "star.fill" : "star")
                        .foregroundStyle(item.isShortlisted ? Color.yellow : Color.primary)
                }
                .help("Mark as one of your best (⇧⌘L)")
                Spacer()
                ForEach(FinderTag.allCases) { tag in
                    let on = item.colorTags.contains(tag)
                    Button {
                        model.toggleTag(tag, for: [item.id])
                    } label: {
                        ZStack {
                            Circle().fill(TagDot.color(for: tag))
                            if on {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0.6 : 0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(tag.rawValue)
                }
            }
            .controlSize(.small)
            if !item.customTags.isEmpty {
                Text("Other tags: " + item.customTags.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Multiple selection

private struct MultiSelectionInspector: View {
    let items: [FileItem]

    private var totalBytes: Int64 {
        items.reduce(0) { $0 + ($1.kind == .folder ? ($1.meta?.folderSize ?? 0) : $1.fileSize) }
    }

    private var uniqueDimensions: [String] {
        Array(Set(items.map(\.dimensionsText).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(items.count) items selected")
                .font(.headline)
            InspectorSection(title: "Summary", rows: [
                ("Total size", Formatters.bytes(totalBytes)),
                ("Images", "\(items.filter { $0.kind == .image }.count)"),
                ("Videos", "\(items.filter { $0.kind == .video }.count)"),
                ("Folders", "\(items.filter { $0.kind == .folder }.count)")
            ])
            if !uniqueDimensions.isEmpty {
                InspectorSection(title: uniqueDimensions.count == 1 ? "Dimensions (all)" : "Dimensions", rows:
                    uniqueDimensions.prefix(12).map { dims in
                        (dims, "\(items.filter { $0.dimensionsText == dims }.count)×")
                    }
                )
            }
            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Nothing selected

private struct FolderSummaryInspector: View {
    @EnvironmentObject private var model: FolderModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.currentURL?.lastPathComponent ?? "Folder", systemImage: "folder.fill")
                .font(.headline)
                .lineLimit(2)
            InspectorSection(title: "This folder", rows: [
                ("Items", "\(model.items.count)"),
                ("Images", "\(model.items.filter { $0.kind == .image }.count)"),
                ("Videos", "\(model.items.filter { $0.kind == .video }.count)"),
                ("Folders", "\(model.items.filter { $0.kind == .folder }.count)"),
                ("Files size", Formatters.bytes(model.items.filter { $0.kind != .folder }.reduce(0) { $0 + $1.fileSize }))
            ])
            Text("Select an item to see its dimensions and camera data. Press Space for a full-size Quick Look preview.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(14)
    }
}

// MARK: - Section layout

private struct InspectorSection: View {
    let title: String
    let rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .kerning(0.5)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.0)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .trailing)
                        Text(row.1)
                            .font(.callout)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }
}
