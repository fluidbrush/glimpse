import Foundation
import UniformTypeIdentifiers

// MARK: - Kinds & filters

enum ItemKind: String, CaseIterable, Identifiable {
    case folder, image, video, audio, pdf, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .folder: return "Folder"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .pdf: return "PDF"
        case .other: return "File"
        }
    }

    var symbol: String {
        switch self {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .pdf: return "doc.richtext"
        case .other: return "doc"
        }
    }
}

enum TypeFilter: String, CaseIterable, Identifiable {
    case all, images, videos, media, folders, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Everything"
        case .images: return "Images"
        case .videos: return "Videos"
        case .media: return "Images & Videos"
        case .folders: return "Folders"
        case .other: return "Other files"
        }
    }

    func matches(_ item: FileItem) -> Bool {
        switch self {
        case .all: return true
        case .images: return item.kind == .image
        case .videos: return item.kind == .video
        case .media: return item.kind == .image || item.kind == .video
        case .folders: return item.kind == .folder
        case .other: return item.kind == .other || item.kind == .audio || item.kind == .pdf
        }
    }
}

enum ViewMode: String, CaseIterable {
    case list, grid
}

/// Finder's colour tags. Stored in the file's `com.apple.metadata:_kMDItemUserTags`
/// extended attribute, so tags set here show up in Finder and vice versa.
enum FinderTag: String, CaseIterable, Identifiable {
    case red = "Red", orange = "Orange", yellow = "Yellow", green = "Green"
    case blue = "Blue", purple = "Purple", gray = "Gray"

    var id: String { rawValue }

    /// Finder's colour index for the tag xattr ("Red\n6").
    var finderIndex: Int {
        switch self {
        case .gray: return 1
        case .green: return 2
        case .purple: return 3
        case .blue: return 4
        case .yellow: return 5
        case .red: return 6
        case .orange: return 7
        }
    }

    /// sRGB components matching Finder's swatches.
    var rgb: (Double, Double, Double) {
        switch self {
        case .red: return (1.00, 0.32, 0.34)
        case .orange: return (1.00, 0.66, 0.18)
        case .yellow: return (1.00, 0.85, 0.18)
        case .green: return (0.36, 0.82, 0.33)
        case .blue: return (0.18, 0.55, 1.00)
        case .purple: return (0.78, 0.42, 1.00)
        case .gray: return (0.56, 0.56, 0.58)
        }
    }

    static func named(_ name: String) -> FinderTag? {
        allCases.first { $0.rawValue.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// The tag name used for the shortlist ("best work") star. It is an ordinary
/// Finder tag, so a shortlisted file is also findable in Finder and Spotlight.
let shortlistTagName = "Shortlist"

/// Which tagged items to show.
enum TagFilter: Hashable {
    case any
    case shortlist
    case color(FinderTag)
    case untagged

    var label: String {
        switch self {
        case .any: return "All items"
        case .shortlist: return "Shortlisted"
        case .color(let tag): return tag.rawValue
        case .untagged: return "Untagged"
        }
    }

    func matches(_ item: FileItem) -> Bool {
        switch self {
        case .any: return true
        case .shortlist: return item.isShortlisted
        case .color(let tag): return item.colorTags.contains(tag)
        case .untagged: return item.tags.isEmpty
        }
    }
}

enum MetaState {
    case pending, loaded
}

// MARK: - Metadata

struct GPSCoordinate {
    var latitude: Double
    var longitude: Double

    var text: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}

struct MediaMeta {
    // Pixel / page geometry
    var width: Int?
    var height: Int?
    var pageSize: CGSize?        // PDF, in points
    var pageCount: Int?
    var frameCount: Int?         // animated GIF / multi-frame
    var dpi: Double?
    var orientation: Int?

    // Colour
    var colorModel: String?
    var depth: Int?
    var hasAlpha: Bool?
    var profile: String?

    // Camera
    var make: String?
    var model: String?
    var lens: String?
    var software: String?
    var iso: Int?
    var fNumber: Double?
    var exposure: Double?        // seconds
    var focalLength: Double?     // mm
    var focalLength35: Int?      // mm, 35 mm equivalent
    var dateTaken: Date?
    var gps: GPSCoordinate?

    // Video / audio
    var duration: Double?        // seconds
    var fps: Double?
    var codec: String?
    var bitrate: Double?         // bits per second
    var audioCodec: String?
    var sampleRate: Double?
    var channels: Int?

    // Folder
    var itemCount: Int?
    var folderSize: Int64?

    var error: String?
}

// MARK: - File item

struct FileItem: Identifiable {
    let id: String
    let url: URL
    let name: String
    let kind: ItemKind
    let contentType: UTType?
    let fileSize: Int64
    let modified: Date
    let created: Date?
    let isHidden: Bool
    var tags: [String]
    var meta: MediaMeta?
    var metaState: MetaState = .pending

    init(url: URL, kind: ItemKind, contentType: UTType?, fileSize: Int64, modified: Date, created: Date?, isHidden: Bool, tags: [String] = []) {
        self.id = url.path
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.contentType = contentType
        self.fileSize = fileSize
        self.modified = modified
        self.created = created
        self.isHidden = isHidden
        self.tags = tags
    }

    // MARK: Tags

    var isShortlisted: Bool {
        tags.contains { $0.caseInsensitiveCompare(shortlistTagName) == .orderedSame }
    }

    var colorTags: [FinderTag] {
        tags.compactMap(FinderTag.named)
    }

    /// Other (custom) tags that are neither colours nor the shortlist marker.
    var customTags: [String] {
        tags.filter { FinderTag.named($0) == nil && $0.caseInsensitiveCompare(shortlistTagName) != .orderedSame }
    }

    var sortShortlist: Int { isShortlisted ? 0 : 1 }
    var sortTags: String { (isShortlisted ? "0" : "1") + tags.sorted().joined(separator: ",") }
    var tagsText: String {
        var parts: [String] = []
        if isShortlisted { parts.append("★") }
        parts.append(contentsOf: colorTags.map(\.rawValue))
        parts.append(contentsOf: customTags)
        return parts.joined(separator: " ")
    }

    // MARK: Sort helpers (Table columns need Comparable values)

    var kindLabel: String {
        if kind == .folder { return "Folder" }
        let ext = url.pathExtension.uppercased()
        if !ext.isEmpty { return ext }
        return contentType?.localizedDescription ?? kind.label
    }

    var sortWidth: Int { meta?.width ?? -1 }
    var sortHeight: Int { meta?.height ?? -1 }
    var sortPixels: Int {
        if let w = meta?.width, let h = meta?.height { return w * h }
        if let n = meta?.itemCount { return -1_000_000 + n }
        return -1
    }
    var sortMegapixels: Double {
        guard let w = meta?.width, let h = meta?.height else { return -1 }
        return Double(w * h) / 1_000_000
    }
    var sortSize: Int64 { meta?.folderSize ?? fileSize }
    var sortCreated: Date { created ?? .distantPast }
    var sortCamera: String { cameraText }
    var sortLens: String { meta?.lens ?? "" }
    var sortISO: Int { meta?.iso ?? -1 }
    var sortAperture: Double { meta?.fNumber ?? -1 }
    var sortExposure: Double { meta?.exposure ?? -1 }
    var sortFocal: Double { meta?.focalLength ?? -1 }
    var sortDateTaken: Date { meta?.dateTaken ?? .distantPast }
    var sortDuration: Double { meta?.duration ?? -1 }
    var sortFPS: Double { meta?.fps ?? -1 }
    var sortCodec: String { meta?.codec ?? "" }
    var sortColor: String { colorText }
    var sortDPI: Double { meta?.dpi ?? -1 }
    var sortAspect: Double {
        guard let w = meta?.width, let h = meta?.height, h > 0 else { return -1 }
        return Double(w) / Double(h)
    }

    // MARK: Display text

    var hasDimensions: Bool { meta?.width != nil && meta?.height != nil }

    var dimensionsText: String {
        if let w = meta?.width, let h = meta?.height { return "\(w) × \(h)" }
        if let s = meta?.pageSize { return "\(Int(s.width.rounded())) × \(Int(s.height.rounded())) pt" }
        if kind == .folder, let n = meta?.itemCount { return n == 1 ? "1 item" : "\(n) items" }
        return ""
    }

    var widthText: String { meta?.width.map(String.init) ?? "" }
    var heightText: String { meta?.height.map(String.init) ?? "" }

    var megapixelsText: String {
        guard let w = meta?.width, let h = meta?.height, kind == .image else { return "" }
        let mp = Double(w * h) / 1_000_000
        return mp < 0.1 ? String(format: "%.2f MP", mp) : String(format: "%.1f MP", mp)
    }

    var aspectText: String {
        guard let w = meta?.width, let h = meta?.height, w > 0, h > 0 else { return "" }
        return Formatters.aspectRatio(w, h)
    }

    var sizeText: String {
        if kind == .folder {
            if let s = meta?.folderSize { return Formatters.bytes(s) }
            return ""
        }
        return Formatters.bytes(fileSize)
    }

    var cameraText: String {
        guard let meta else { return "" }
        let make = meta.make?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = meta.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if model.isEmpty { return make }
        if make.isEmpty { return model }
        if model.lowercased().hasPrefix(make.lowercased()) { return model }
        return "\(make) \(model)"
    }

    var isoText: String { meta?.iso.map { "ISO \($0)" } ?? "" }
    var apertureText: String { meta?.fNumber.map(Formatters.aperture) ?? "" }
    var exposureText: String { meta?.exposure.map(Formatters.exposure) ?? "" }
    var focalText: String {
        guard let f = meta?.focalLength else { return "" }
        return Formatters.millimetres(f)
    }
    var dateTakenText: String { meta?.dateTaken.map(Formatters.dateTime) ?? "" }
    var durationText: String { meta?.duration.map(Formatters.duration) ?? "" }
    var fpsText: String {
        guard let fps = meta?.fps, fps > 0 else { return "" }
        return fps.rounded() == fps ? "\(Int(fps)) fps" : String(format: "%.2f fps", fps)
    }
    var codecText: String { meta?.codec ?? "" }
    var bitrateText: String {
        guard let b = meta?.bitrate, b > 0 else { return "" }
        return Formatters.bitrate(b)
    }
    var colorText: String {
        guard let meta, kind == .image else { return "" }
        var parts: [String] = []
        if let c = meta.colorModel { parts.append(c) }
        if let d = meta.depth { parts.append("\(d)-bit") }
        if meta.hasAlpha == true { parts.append("alpha") }
        return parts.joined(separator: " · ")
    }
    var dpiText: String {
        guard let d = meta?.dpi, d > 0 else { return "" }
        return d.rounded() == d ? "\(Int(d)) dpi" : String(format: "%.1f dpi", d)
    }
    var modifiedText: String { Formatters.dateTime(modified) }
    var createdText: String { created.map(Formatters.dateTime) ?? "" }
}

// MARK: - Formatters

enum Formatters {
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }()

    static func bytes(_ n: Int64) -> String {
        byteFormatter.string(fromByteCount: n)
    }

    static func dateTime(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    static func aperture(_ f: Double) -> String {
        if f.rounded() == f { return "ƒ/\(Int(f))" }
        return String(format: "ƒ/%.1f", f)
    }

    static func exposure(_ s: Double) -> String {
        guard s > 0 else { return "" }
        if s >= 1 {
            return s.rounded() == s ? "\(Int(s)) s" : String(format: "%.1f s", s)
        }
        let denom = (1.0 / s).rounded()
        return "1/\(Int(denom)) s"
    }

    static func millimetres(_ mm: Double) -> String {
        if mm.rounded() == mm { return "\(Int(mm)) mm" }
        return String(format: "%.1f mm", mm)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "" }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        if total < 10 { return String(format: "%.1f s", seconds) }
        return String(format: "%d:%02d", m, s)
    }

    static func bitrate(_ bps: Double) -> String {
        if bps >= 1_000_000 { return String(format: "%.1f Mbps", bps / 1_000_000) }
        return String(format: "%.0f kbps", bps / 1000)
    }

    static func aspectRatio(_ w: Int, _ h: Int) -> String {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = max(gcd(w, h), 1)
        let rw = w / g, rh = h / g
        if rw <= 32 && rh <= 32 { return "\(rw):\(rh)" }
        let r = Double(w) / Double(h)
        // Snap to common ratios when very close.
        let common: [(String, Double)] = [
            ("16:9", 16.0 / 9), ("9:16", 9.0 / 16), ("4:3", 4.0 / 3), ("3:4", 3.0 / 4),
            ("3:2", 1.5), ("2:3", 2.0 / 3), ("21:9", 21.0 / 9), ("1:1", 1), ("5:4", 1.25), ("4:5", 0.8),
            ("1.85:1", 1.85), ("2.39:1", 2.39)
        ]
        for (name, value) in common where abs(r - value) < 0.01 { return name }
        return String(format: "%.2f:1", r)
    }
}
