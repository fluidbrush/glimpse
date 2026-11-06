<p align="center">
  <img src="Resources/AppIcon-source.png" width="128" alt="Glimpse icon">
</p>

<h1 align="center">Glimpse</h1>

<p align="center">
  A Finder for people who care about pixels.<br>
  Browse folders and see every image and video's <b>dimensions, camera data, duration and codec</b> at a glance — no Get Info, no mixed-media confusion.
</p>

<p align="center">
  <a href="https://fluidbrush.github.io/glimpse/">Website</a> ·
  <a href="https://github.com/fluidbrush/glimpse/releases/latest">Download the latest DMG</a> ·
  macOS 14 Sonoma or newer · Apple Silicon &amp; Intel · Free, MIT-licensed
</p>

---

## Why

Finder shows pixel dimensions only if you open Get Info, and gives up entirely when a folder mixes photos, screenshots, videos and PSDs. Designers and photographers end up opening files one by one just to check a size. Glimpse puts the numbers in the list.

## Features

- **Dimensions column** for images (EXIF-orientation aware), videos (rotation applied), SVG (width/height or viewBox), PDF/AI (page size, page count), animated GIF (frame count)
- **Camera data** – camera, lens, ISO, aperture, shutter, focal length (35 mm equivalent), date taken, GPS; for videos, the make/model and date the phone wrote
- **Video** – duration, frame rate, codec (H.264 / HEVC / ProRes / AV1 …), bit rate, audio format
- **21 customisable columns**, all sortable, remembered between launches
- **List or thumbnail view** (⌘1 / ⌘2) with a thumbnail size slider
- **Quick Look** with Space, exactly like Finder; arrow keys move through the folder
- **Inspector** with a large preview and *Copy Size* / *Copy CSS* buttons
- **Shortlist & tags** – star your best work (⇧⌘L) and apply Finder colour tags (⌃1–7). They are real Finder tags, so they show up in Finder and Spotlight too; filter the view by them from the toolbar
- **Finder-style file management** – copy, paste, move (⌥⌘V), duplicate (⌘D → `copy_name`), rename (Return or ⇧⌘R), new folder, new folder with selection, copy/move to a folder of your choice, move to Trash
- **Filters** – everything / images / videos / folders / other, plus name search
- Sidebar with Places, Favorites, Volumes and Recent folders; drag a folder onto the window to open it

Formats: JPEG, PNG, GIF, WebP, HEIC/HEIF, AVIF, TIFF, PSD, BMP, SVG, camera RAW (DNG, CR2/CR3, NEF, ARW, RAF, ORF, RW2…), MP4/MOV/M4V, MP3/M4A/WAV, PDF/AI.

## Install

1. Download `Glimpse-x.y.z.dmg` from the [releases page](https://github.com/fluidbrush/glimpse/releases/latest).
2. Open it and drag **Glimpse** into **Applications**.
3. First launch: the app is signed ad-hoc (no Apple Developer ID yet), so macOS may say it "cannot verify the developer". Right-click the app → **Open** → **Open**. You only need to do this once.
4. macOS will ask permission the first time you browse Desktop, Documents or Downloads.

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`) or Xcode.

```bash
git clone https://github.com/fluidbrush/glimpse.git
cd glimpse
./build.sh            # universal app + DMG in dist/
./build.sh --native   # faster: this Mac's architecture only
./build.sh --run      # build and launch
```

To work in Xcode: `open Package.swift`, then run the `Glimpse` scheme.

The version number comes from the `VERSION` file.

## How it stays fast and light

- Only the folder you are looking at is scanned; nothing crawls your disk.
- Metadata is read from file headers with ImageIO and AVFoundation — pixels are never decoded just to get a size.
- Files are read 2–6 at a time in the background, results are applied in batches, and the scan is cancelled the moment you change folder. ⌘R re-reads only the current folder.
- Thumbnails use the embedded camera preview when there is one and are kept in a bounded cache (~256 MB max). Settings (⌘,) can turn list-view thumbnails off for instant file icons.
- Folder sizes are off by default because they require walking sub-folders.

## Privacy & security

- Glimpse makes **no network connections** and has no analytics or telemetry.
- It reads only the folders you open. The only things it writes are the files you ask it to (copy, move, rename, trash, new folder) and Finder tags on files you tag.
- Preferences (view options, favourite and recent folder paths) are stored locally in `~/Library/Preferences/com.fluidbrush.glimpse.plist`.
- Deleting always goes through the Trash.
- The app is not sandboxed, because a sandboxed app cannot browse arbitrary folders the way a file browser needs to. It is built with the hardened runtime and signed ad-hoc; a Developer ID / notarised build is planned.

## Project layout

```
Package.swift             Swift Package (executable target)
VERSION                   version number used by build.sh
build.sh                  builds the .app and the drag-to-Applications .dmg
Scripts/MakeIcon.swift    masks the square icon artwork into the macOS icon shape
Resources/                Info.plist, icon artwork, DMG background
Sources/Glimpse/
  GlimpseApp.swift        app entry, menus & shortcuts, Settings scene
  FolderModel.swift       folder scanning, navigation, file operations, tags
  MetadataReader.swift    ImageIO / AVFoundation / PDF / SVG readers
  ThumbnailLoader.swift   ImageIO + Quick Look thumbnails, bounded cache
  Models.swift            FileItem, MediaMeta, tags, formatters
  ContentView.swift       window, toolbar, inspector wiring
  SidebarView.swift       places / favourites / volumes / recents
  BrowserView.swift       path bar, status bar, Quick Look, rename sheet
  BrowserListView.swift   Table with customisable columns, context menu
  BrowserGridView.swift   thumbnail grid
  InspectorView.swift     detail panel + tag editor
  SettingsView.swift      Settings window (⌘,)
```

## Website

The landing page lives in `docs/` and is served by GitHub Pages at https://fluidbrush.github.io/glimpse/. It is a single static HTML file; the download buttons read the newest release from the GitHub API.

## Contributing

Issues and pull requests are welcome. Keep changes focused; the app deliberately depends on nothing outside the macOS SDK.

## License

MIT © 2026 [Fluidbrush](https://github.com/fluidbrush)
