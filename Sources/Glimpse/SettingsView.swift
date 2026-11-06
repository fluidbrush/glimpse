import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: FolderModel

    var body: some View {
        Form {
            Section("List view") {
                Toggle("Show thumbnails next to file names", isOn: $model.showListThumbnails)
                Text("Off shows the file-type icon instead, which is instant. Thumbnails in the Thumbnails view are always shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Folders") {
                Toggle("Show hidden files", isOn: $model.showHidden)
                Toggle("Calculate folder sizes", isOn: $model.computeFolderSizes)
                Text("Folder sizes walk every sub-folder, so this is off by default. Only the folder you are viewing is ever scanned.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sidebar") {
                Stepper(value: $model.recentsLimit, in: 0...20) {
                    HStack {
                        Text("Recent folders to keep")
                        Spacer()
                        Text("\(model.recentsLimit)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Memory") {
                HStack {
                    Text("Thumbnail cache")
                    Spacer()
                    Button("Clear Now") { ThumbnailLoader.shared.clear() }
                }
                Text("Thumbnails are kept in a bounded cache (about 256 MB max) and dropped automatically when memory is needed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
