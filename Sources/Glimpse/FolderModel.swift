import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FolderModel: ObservableObject {

    // MARK: Browsing state

    @Published private(set) var currentURL: URL?
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isScanning = false
    @Published private(set) var loadedCount = 0
    @Published var selection = Set<FileItem.ID>()
    @Published var searchText = ""
    @Published var typeFilter: TypeFilter = .all
    @Published var tagFilter: TagFilter = .any
    /// Item currently being renamed (drives the rename sheet).
    @Published var renameTarget: FileItem?
    @Published var renameText = ""
    @Published var errorMessage: String?

    // MARK: Persisted UI options

    @Published var viewMode: ViewMode {
        didSet { defaults.set(viewMode.rawValue, forKey: Keys.viewMode) }
    }
    @Published var showHidden: Bool {
        didSet { defaults.set(showHidden, forKey: Keys.showHidden); rescan() }
    }
    @Published var computeFolderSizes: Bool {
        didSet { defaults.set(computeFolderSizes, forKey: Keys.folderSizes); if computeFolderSizes { rescan() } }
    }
    @Published var showInspector: Bool {
        didSet { defaults.set(showInspector, forKey: Keys.inspector) }
    }
    @Published var gridThumbSize: Double {
        didSet { defaults.set(gridThumbSize, forKey: Keys.thumbSize) }
    }
    @Published private(set) var recents: [URL] {
        didSet { defaults.set(recents.map(\.path), forKey: Keys.recents) }
    }
    @Published private(set) var favorites: [URL] {
        didSet { defaults.set(favorites.map(\.path), forKey: Keys.favorites) }
    }
    /// Thumbnails in the list view (off = instant file-type icons).
    @Published var showListThumbnails: Bool {
        didSet { defaults.set(showListThumbnails, forKey: Keys.listThumbs) }
    }
    @Published var recentsLimit: Int {
        didSet {
            defaults.set(recentsLimit, forKey: Keys.recentsLimit)
            if recents.count > recentsLimit { recents = Array(recents.prefix(recentsLimit)) }
        }
    }

    /// The item shown in the Quick Look panel (nil = panel closed).
    @Published var quickLookURL: URL?
    @Published var isBusy = false

    private enum Keys {
        static let viewMode = "viewMode"
        static let showHidden = "showHidden"
        static let folderSizes = "computeFolderSizes"
        static let inspector = "showInspector"
        static let thumbSize = "gridThumbSize"
        static let recents = "recentFolders"
        static let favorites = "favoriteFolders"
        static let lastFolder = "lastFolder"
        static let listThumbs = "showListThumbnails"
        static let recentsLimit = "recentsLimit"
    }

    private let defaults = UserDefaults.standard
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []
    private var scanTask: Task<Void, Never>?

    // MARK: Init

    init() {
        viewMode = ViewMode(rawValue: defaults.string(forKey: Keys.viewMode) ?? "") ?? .list
        showHidden = defaults.bool(forKey: Keys.showHidden)
        computeFolderSizes = defaults.bool(forKey: Keys.folderSizes)
        showInspector = defaults.object(forKey: Keys.inspector) as? Bool ?? true
        gridThumbSize = defaults.object(forKey: Keys.thumbSize) as? Double ?? 128
        showListThumbnails = defaults.object(forKey: Keys.listThumbs) as? Bool ?? true
        let limit = defaults.object(forKey: Keys.recentsLimit) as? Int ?? 5
        recentsLimit = limit
        recents = Array((defaults.stringArray(forKey: Keys.recents) ?? []).map { URL(fileURLWithPath: $0) }.prefix(limit))
        favorites = (defaults.stringArray(forKey: Keys.favorites) ?? []).map { URL(fileURLWithPath: $0) }

        let start: URL
        if let last = defaults.string(forKey: Keys.lastFolder), FileManager.default.fileExists(atPath: last) {
            start = URL(fileURLWithPath: last)
        } else if let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first {
            start = pictures
        } else {
            start = FileManager.default.homeDirectoryForCurrentUser
        }
        navigate(to: start)
    }

    // MARK: Navigation

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { (currentURL?.path ?? "/") != "/" }

    func open(_ url: URL) {
        let target = url.standardizedFileURL
        if target == currentURL { return }
        if let current = currentURL { backStack.append(current) }
        forwardStack.removeAll()
        navigate(to: target)
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = currentURL { forwardStack.append(current) }
        navigate(to: previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = currentURL { backStack.append(current) }
        navigate(to: next)
    }

    func goUp() {
        guard let current = currentURL, canGoUp else { return }
        open(current.deletingLastPathComponent())
    }

    private func navigate(to url: URL) {
        currentURL = url
        selection.removeAll()
        quickLookURL = nil
        defaults.set(url.path, forKey: Keys.lastFolder)
        addRecent(url)
        rescan()
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Browse"
        panel.message = "Choose a folder to browse"
        panel.directoryURL = currentURL
        if panel.runModal() == .OK, let url = panel.url {
            open(url)
        }
    }

    // MARK: Recents & favorites

    private func addRecent(_ url: URL) {
        var list = recents.filter { $0 != url }
        list.insert(url, at: 0)
        if list.count > recentsLimit { list = Array(list.prefix(recentsLimit)) }
        recents = list
    }

    func clearRecents() { recents = [] }

    func isFavorite(_ url: URL) -> Bool { favorites.contains(url.standardizedFileURL) }

    func toggleFavorite(_ url: URL) {
        let target = url.standardizedFileURL
        if let index = favorites.firstIndex(of: target) {
            favorites.remove(at: index)
        } else {
            favorites.append(target)
        }
    }

    func removeFavorite(_ url: URL) {
        favorites.removeAll { $0 == url }
    }

    // MARK: Scanning

    func refresh() {
        ThumbnailLoader.shared.clear()
        rescan()
    }

    func rescan() {
        scanTask?.cancel()
        scanGeneration += 1
        guard let url = currentURL else { return }
        isScanning = true
        loadedCount = 0
        metaQueue.removeAll()
        visibleRequests.removeAll()
        inFlight.removeAll()
        let showHidden = self.showHidden
        let generation = scanGeneration

        scanTask = Task { [weak self] in
            let listed = await Task.detached(priority: .userInitiated) {
                FolderModel.list(url, showHidden: showHidden)
            }.value
            guard let self, !Task.isCancelled, generation == self.scanGeneration else { return }
            switch listed {
            case .success(let found):
                self.errorMessage = nil
                self.items = found
                self.applyPendingSelection()
                // Metadata is read progressively: rows that are on screen first
                // (the views call requestMetadata as they appear), the rest trickles
                // in behind at low concurrency.
                self.metaQueue = found.filter { $0.kind != .other }.map(\.id)
                self.loadedCount = found.count - self.metaQueue.count
                self.pumpMetadata()
            case .failure(let error):
                self.items = []
                self.errorMessage = error.localizedDescription
                self.isScanning = false
            }
        }
    }

    // MARK: Progressive metadata scheduler

    private var scanGeneration = 0
    /// Items still waiting for metadata, in listing order.
    private var metaQueue: [String] = []
    /// Items currently on screen that asked to be read first (most recent first).
    private var visibleRequests: [String] = []
    private var inFlight = Set<String>()
    private var applyBuffer: [(String, MediaMeta)] = []
    private var flushScheduled = false
    private let visibleConcurrency = max(3, min(8, ProcessInfo.processInfo.activeProcessorCount))
    private let backgroundConcurrency = 2

    /// Called by list rows and grid cells as they appear on screen.
    func requestMetadata(_ id: FileItem.ID) {
        guard !inFlight.contains(id), metaQueue.contains(id) else { return }
        visibleRequests.removeAll { $0 == id }
        visibleRequests.insert(id, at: 0)
        if visibleRequests.count > 400 { visibleRequests.removeLast(visibleRequests.count - 400) }
        pumpMetadata()
    }

    private func pumpMetadata() {
        let generation = scanGeneration
        let folderSizes = computeFolderSizes
        while true {
            let limit = visibleRequests.isEmpty ? backgroundConcurrency : visibleConcurrency
            guard inFlight.count < limit else { return }
            guard let id = nextMetadataID() else {
                if inFlight.isEmpty { isScanning = false }
                return
            }
            guard let item = items.first(where: { $0.id == id }) else { continue }
            inFlight.insert(id)
            Task { [weak self] in
                let meta = await MetadataReader.read(item, computeFolderSize: folderSizes)
                guard let self, generation == self.scanGeneration else { return }
                self.inFlight.remove(id)
                self.applyBuffer.append((id, meta))
                self.scheduleFlush()
                self.pumpMetadata()
            }
        }
    }

    private func nextMetadataID() -> String? {
        while let id = visibleRequests.first {
            visibleRequests.removeFirst()
            if let index = metaQueue.firstIndex(of: id) {
                metaQueue.remove(at: index)
                return id
            }
        }
        while !metaQueue.isEmpty {
            let id = metaQueue.removeFirst()
            if !inFlight.contains(id) { return id }
        }
        return nil
    }

    /// Results are applied in small batches so the table isn't re-rendered for
    /// every single file (which swallowed clicks while scanning).
    private func scheduleFlush() {
        guard !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self else { return }
            self.flushScheduled = false
            let batch = self.applyBuffer
            self.applyBuffer.removeAll(keepingCapacity: true)
            self.applyBatch(batch)
            if self.metaQueue.isEmpty && self.inFlight.isEmpty && self.applyBuffer.isEmpty { self.isScanning = false }
        }
    }

    private func applyBatch(_ batch: [(String, MediaMeta)]) {
        guard !batch.isEmpty else { return }
        var indexByID: [String: Int] = [:]
        for (index, item) in items.enumerated() { indexByID[item.id] = index }
        var updated = items
        var applied = 0
        for (id, meta) in batch {
            guard let index = indexByID[id] else { continue }
            updated[index].meta = meta
            updated[index].metaState = .loaded
            applied += 1
        }
        items = updated
        loadedCount += applied
    }

    nonisolated private static func list(_ url: URL, showHidden: Bool) -> Result<[FileItem], Error> {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isPackageKey, .contentTypeKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey, .isHiddenKey, .tagNamesKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
        } catch {
            return .failure(error)
        }

        var result: [FileItem] = []
        result.reserveCapacity(urls.count)
        for fileURL in urls {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory ?? false
            let isPackage = values?.isPackage ?? false
            let type = values?.contentType
            let kind = classify(url: fileURL, type: type, isDirectory: isDirectory, isPackage: isPackage)
            let item = FileItem(
                url: fileURL,
                kind: kind,
                contentType: type,
                fileSize: Int64(values?.fileSize ?? 0),
                modified: values?.contentModificationDate ?? .distantPast,
                created: values?.creationDate,
                isHidden: values?.isHidden ?? false,
                tags: values?.tagNames ?? []
            )
            result.append(item)
        }
        result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return .success(result)
    }

    nonisolated private static func classify(url: URL, type: UTType?, isDirectory: Bool, isPackage: Bool) -> ItemKind {
        if isDirectory && !isPackage { return .folder }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "svg", "svgz": return .image
        case "ai": return .pdf
        case "psd", "psb", "heic", "heif", "avif", "webp", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2":
            return .image
        default: break
        }
        guard let type else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        return .other
    }

    // MARK: Derived data

    var filteredItems: [FileItem] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return items.filter { item in
            guard typeFilter.matches(item), tagFilter.matches(item) else { return false }
            if query.isEmpty { return true }
            return item.name.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.id) }
    }

    var selectedItem: FileItem? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return items.first { $0.id == id }
    }

    var summaryText: String {
        let shown = filteredItems
        let folders = shown.filter { $0.kind == .folder }.count
        let images = shown.filter { $0.kind == .image }.count
        let videos = shown.filter { $0.kind == .video }.count
        var parts: [String] = []
        parts.append(shown.count == 1 ? "1 item" : "\(shown.count) items")
        if folders > 0 { parts.append("\(folders) folder\(folders == 1 ? "" : "s")") }
        if images > 0 { parts.append("\(images) image\(images == 1 ? "" : "s")") }
        if videos > 0 { parts.append("\(videos) video\(videos == 1 ? "" : "s")") }
        if shown.count != items.count { parts.append("of \(items.count)") }
        if !selection.isEmpty { parts.append("\(selection.count) selected") }
        return parts.joined(separator: " · ")
    }

    // MARK: Actions on items

    func item(for id: FileItem.ID) -> FileItem? {
        items.first { $0.id == id }
    }

    func openItem(_ item: FileItem) {
        if item.kind == .folder {
            open(item.url)
        } else {
            NSWorkspace.shared.open(item.url)
        }
    }

    func openSelection(_ ids: Set<FileItem.ID>) {
        let chosen = ids.compactMap { item(for: $0) }
        if chosen.count == 1, let only = chosen.first {
            openItem(only)
            return
        }
        for item in chosen where item.kind != .folder {
            NSWorkspace.shared.open(item.url)
        }
    }

    func select(_ id: FileItem.ID, extend: Bool) {
        if extend {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
    }

    func revealInFinder(_ ids: Set<FileItem.ID>) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func copyToPasteboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    func copyDimensions(_ ids: Set<FileItem.ID>) {
        let lines = ids.compactMap { item(for: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { $0.dimensionsText }
            .filter { !$0.isEmpty }
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    func copyPaths(_ ids: Set<FileItem.ID>) {
        let lines = ids.compactMap { item(for: $0)?.url.path }.sorted()
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    func copyNames(_ ids: Set<FileItem.ID>) {
        let lines = ids.compactMap { item(for: $0)?.name }.sorted()
        copyToPasteboard(lines.joined(separator: "\n"))
    }

    func moveToTrash(_ ids: Set<FileItem.ID>) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard !urls.isEmpty else { return }
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                pathDidMove(from: url, to: nil)
            } catch {
                errorMessage = "Couldn't move \(url.lastPathComponent) to Trash: \(error.localizedDescription)"
            }
        }
        selection.removeAll()
        rescan()
    }

    // MARK: Quick Look

    func toggleQuickLook() {
        if quickLookURL != nil {
            quickLookURL = nil
            return
        }
        if let item = selectedItem {
            quickLookURL = item.url
        } else if let first = selection.first, let item = self.item(for: first) {
            quickLookURL = item.url
        }
    }

    func showQuickLook(_ item: FileItem) {
        selection = [item.id]
        quickLookURL = item.url
    }

    // MARK: Clipboard (file URLs – interoperable with Finder)

    func copyToClipboard(_ ids: Set<FileItem.ID>) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls.map { $0 as NSURL })
    }

    var clipboardFileURLs: [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objects = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return objects.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var canPaste: Bool { !clipboardFileURLs.isEmpty }

    /// ⌘V copies the clipboard files into the current folder; ⌥⌘V moves them (like Finder).
    func pasteFromClipboard(move: Bool) {
        guard let destination = currentURL else { return }
        let sources = clipboardFileURLs
        guard !sources.isEmpty else { return }
        transfer(sources, to: destination, move: move)
    }

    func duplicate(_ ids: Set<FileItem.ID>) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard !urls.isEmpty else { return }
        runFileOperation { fm in
            var created: [URL] = []
            for url in urls {
                let folder = url.deletingLastPathComponent()
                var target = folder.appendingPathComponent("copy_" + url.lastPathComponent)
                var n = 2
                while fm.fileExists(atPath: target.path) {
                    target = folder.appendingPathComponent("copy_\(n)_" + url.lastPathComponent)
                    n += 1
                }
                try fm.copyItem(at: url, to: target)
                created.append(target)
            }
            return created
        }
    }

    /// Lets the user pick (or create) a destination folder, then copies or moves the items there.
    func transferToChosenFolder(_ ids: Set<FileItem.ID>, move: Bool) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL
        let count = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
        panel.message = move ? "Move \(count) to…" : "Copy \(count) to…"
        panel.prompt = move ? "Move" : "Copy"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        transfer(urls, to: destination, move: move)
    }

    func newFolder() {
        guard let parent = currentURL else { return }
        runFileOperation { fm in
            let target = FolderModel.uniqueURL(for: parent.appendingPathComponent("untitled folder"), fm: fm)
            try fm.createDirectory(at: target, withIntermediateDirectories: false)
            return [target]
        }
    }

    /// Finder's "New Folder with Selection": creates a folder next to the items and moves them in.
    func newFolderWithSelection(_ ids: Set<FileItem.ID>) {
        let urls = ids.compactMap { item(for: $0)?.url }
        guard let parent = currentURL, !urls.isEmpty else { return }
        let name = urls.count == 1 ? "New Folder with \(urls[0].deletingPathExtension().lastPathComponent)" : "New Folder with Items"
        runFileOperation { fm in
            let folder = FolderModel.uniqueURL(for: parent.appendingPathComponent(name), fm: fm)
            try fm.createDirectory(at: folder, withIntermediateDirectories: false)
            for url in urls {
                try fm.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            }
            return [folder]
        }
    }

    private func transfer(_ sources: [URL], to destination: URL, move: Bool) {
        if move {
            for source in sources {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
                   source.deletingLastPathComponent().standardizedFileURL != destination.standardizedFileURL {
                    pathDidMove(from: source, to: destination.appendingPathComponent(source.lastPathComponent))
                }
            }
        }
        runFileOperation { fm in
            var created: [URL] = []
            for source in sources {
                let sameFolder = source.deletingLastPathComponent().standardizedFileURL == destination.standardizedFileURL
                if move && sameFolder { continue }
                if destination.path.hasPrefix(source.path + "/") {
                    throw NSError(domain: "Glimpse", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Can't put “\(source.lastPathComponent)” inside itself."
                    ])
                }
                var target = destination.appendingPathComponent(source.lastPathComponent)
                if sameFolder {
                    target = destination.appendingPathComponent("copy_" + source.lastPathComponent)
                }
                target = FolderModel.uniqueURL(for: target, fm: fm)
                if move {
                    try fm.moveItem(at: source, to: target)
                } else {
                    try fm.copyItem(at: source, to: target)
                }
                created.append(target)
            }
            return created
        }
    }

    /// Runs a file operation off the main thread, then re-reads the folder and selects what was created.
    private func runFileOperation(_ work: @escaping (FileManager) throws -> [URL]) {
        isBusy = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                do { return .success(try work(FileManager.default)) } catch { return .failure(error) }
            }.value
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success(let created):
                self.rescanThenSelect(created)
            case .failure(let error):
                self.errorMessage = error.localizedDescription
                self.rescan()
            }
        }
    }

    private var pendingSelection: [URL] = []

    private func rescanThenSelect(_ urls: [URL]) {
        pendingSelection = urls
        rescan()
    }

    /// Called after a scan completes to apply a selection requested by a file operation.
    private func applyPendingSelection() {
        guard !pendingSelection.isEmpty, let current = currentURL else { return }
        let inCurrent = pendingSelection.filter { $0.deletingLastPathComponent().standardizedFileURL == current }
        pendingSelection = []
        let ids = Set(inCurrent.map { $0.standardizedFileURL.path }).filter { id in items.contains { $0.id == id } }
        if !ids.isEmpty { selection = ids }
    }

    // MARK: Rename

    func beginRename(_ ids: Set<FileItem.ID>) {
        guard ids.count == 1, let id = ids.first, let item = item(for: id) else { return }
        renameText = item.name
        renameTarget = item
    }

    func commitRename() {
        guard let item = renameTarget else { return }
        renameTarget = nil
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != item.name, !newName.contains("/") else { return }
        let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName)
        if FileManager.default.fileExists(atPath: destination.path) {
            errorMessage = "“\(newName)” already exists in this folder."
            return
        }
        let source = item.url
        if item.kind == .folder { pathDidMove(from: source, to: destination) }
        runFileOperation { fm in
            try fm.moveItem(at: source, to: destination)
            return [destination]
        }
    }

    /// Keeps Favorites, Recent, and the back/forward history pointing at a folder
    /// after it has been renamed or moved. `to == nil` means it is gone (trashed).
    private func pathDidMove(from oldURL: URL, to newURL: URL?) {
        let oldPath = oldURL.standardizedFileURL.path
        func remap(_ url: URL) -> URL? {
            let path = url.standardizedFileURL.path
            if path == oldPath { return newURL?.standardizedFileURL }
            if path.hasPrefix(oldPath + "/") {
                guard let newURL else { return nil }
                return URL(fileURLWithPath: newURL.standardizedFileURL.path + String(path.dropFirst(oldPath.count)))
            }
            return url
        }
        favorites = favorites.compactMap(remap)
        recents = recents.compactMap(remap)
        backStack = backStack.compactMap(remap)
        forwardStack = forwardStack.compactMap(remap)
        if let current = currentURL, let remapped = remap(current), remapped != current {
            currentURL = remapped
            defaults.set(remapped.path, forKey: Keys.lastFolder)
        }
    }

    // MARK: Tags & shortlist (Finder-compatible)

    func toggleShortlist(_ ids: Set<FileItem.ID>) {
        let chosen = ids.compactMap { item(for: $0) }
        guard !chosen.isEmpty else { return }
        // If every selected item is shortlisted, un-shortlist; otherwise shortlist all.
        let allShortlisted = chosen.allSatisfy(\.isShortlisted)
        for item in chosen {
            var tags = item.tags.filter { $0.caseInsensitiveCompare(shortlistTagName) != .orderedSame }
            if !allShortlisted { tags.insert(shortlistTagName, at: 0) }
            writeTags(tags, to: item)
        }
    }

    func toggleTag(_ tag: FinderTag, for ids: Set<FileItem.ID>) {
        let chosen = ids.compactMap { item(for: $0) }
        guard !chosen.isEmpty else { return }
        let allHave = chosen.allSatisfy { $0.colorTags.contains(tag) }
        for item in chosen {
            var tags = item.tags.filter { FinderTag.named($0) != tag }
            if !allHave { tags.append(tag.rawValue) }
            writeTags(tags, to: item)
        }
    }

    /// Removes colour and custom tags but keeps the shortlist star.
    func clearTags(_ ids: Set<FileItem.ID>) {
        for item in ids.compactMap({ item(for: $0) }) {
            writeTags(item.isShortlisted ? [shortlistTagName] : [], to: item)
        }
    }

    /// Writes the tag list to the file's Finder tag attribute and updates the row in place.
    private func writeTags(_ tags: [String], to item: FileItem) {
        do {
            try FolderModel.writeFinderTags(tags, to: item.url)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index].tags = tags
            }
        } catch {
            errorMessage = "Couldn't update tags for \(item.name): \(error.localizedDescription)"
        }
    }

    /// Finder stores tags as a binary plist array of "Name\n<colourIndex>" strings in
    /// the `com.apple.metadata:_kMDItemUserTags` extended attribute.
    nonisolated private static func writeFinderTags(_ tags: [String], to url: URL) throws {
        let entries: [String] = tags.map { name in
            if let color = FinderTag.named(name) { return "\(color.rawValue)\n\(color.finderIndex)" }
            return "\(name)\n0"
        }
        let attribute = "com.apple.metadata:_kMDItemUserTags"
        let result: Int32
        if entries.isEmpty {
            result = removexattr(url.path, attribute, 0)
            if result != 0 && errno == ENOATTR { return }
        } else {
            let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
            result = data.withUnsafeBytes { buffer in
                setxattr(url.path, attribute, buffer.baseAddress, buffer.count, 0, 0)
            }
        }
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: nil)
        }
    }

    nonisolated private static func uniqueURL(for url: URL, fm: FileManager) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = ext.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
