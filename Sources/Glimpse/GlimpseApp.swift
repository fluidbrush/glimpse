import SwiftUI

@main
struct GlimpseApp: App {
    @StateObject private var model = FolderModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 780)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { model.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("New Folder") { model.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("New Folder with Selection") { model.newFolderWithSelection(model.selection) }
                    .keyboardShortcut("n", modifiers: [.command, .control])
                    .disabled(model.selection.isEmpty)
                Divider()
                Button("Quick Look") { model.toggleQuickLook() }
                    .keyboardShortcut("y", modifiers: .command)
                    .disabled(model.selection.isEmpty)
            }

            // Edit menu: Copy/Paste come from the standard items (onCopyCommand / onPasteCommand);
            // these are the Finder-style extras.
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Move Items Here") { model.pasteFromClipboard(move: true) }
                    .keyboardShortcut("v", modifiers: [.command, .option])
                Button("Duplicate") { model.duplicate(model.selection) }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(model.selection.isEmpty)
                Button("Rename…") { model.beginRename(model.selection) }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(model.selection.count != 1)
                Button("Copy to Folder…") { model.transferToChosenFolder(model.selection, move: false) }
                    .disabled(model.selection.isEmpty)
                Button("Move to Folder…") { model.transferToChosenFolder(model.selection, move: true) }
                    .disabled(model.selection.isEmpty)
                Divider()
                Button("Move to Trash") { model.moveToTrash(model.selection) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(model.selection.isEmpty)
                Divider()
                TagMenuItems(model: model, ids: model.selection)
            }

            CommandMenu("Go") {
                Button("Back") { model.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!model.canGoBack)
                Button("Forward") { model.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!model.canGoForward)
                Button("Enclosing Folder") { model.goUp() }
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .disabled(!model.canGoUp)
                Divider()
                Button("Refresh") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                Divider()
                Button(model.currentURL.map { model.isFavorite($0) } == true ? "Remove from Favorites" : "Add to Favorites") {
                    if let url = model.currentURL { model.toggleFavorite(url) }
                }
                .keyboardShortcut("t", modifiers: [.command, .control])
            }

            CommandGroup(after: .toolbar) {
                Button("as List") { model.viewMode = .list }
                    .keyboardShortcut("1", modifiers: .command)
                Button("as Thumbnails") { model.viewMode = .grid }
                    .keyboardShortcut("2", modifiers: .command)
                Divider()
                Toggle("Thumbnails in List View", isOn: $model.showListThumbnails)
                Toggle("Show Hidden Files", isOn: $model.showHidden)
                    .keyboardShortcut(".", modifiers: [.command, .shift])
                Toggle("Calculate Folder Sizes", isOn: $model.computeFolderSizes)
                Divider()
                Toggle("Show Inspector", isOn: $model.showInspector)
                    .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
