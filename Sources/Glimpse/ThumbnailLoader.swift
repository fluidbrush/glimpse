import AppKit
import ImageIO
import QuickLookThumbnailing

/// Produces thumbnails as cheaply as possible:
///  - images: ImageIO, which uses the embedded EXIF/HEIC preview when present and
///    otherwise decodes a downsampled version (no full-size decode),
///  - video / PDF / anything else visual: Quick Look,
///  - folders & other files: the Finder icon (instant, cached by the system).
/// Results live in a bounded cache so big folders don't grow memory without limit.
final class ThumbnailLoader: @unchecked Sendable {
    static let shared = ThumbnailLoader()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 2000
        c.totalCostLimit = 256 * 1024 * 1024   // ~256 MB of decoded pixels
        return c
    }()

    /// ImageIO work runs here, limited so a big folder can't swamp the CPU.
    private let imageQueue = DispatchQueue(label: "com.fluidbrush.glimpse.thumbs", qos: .userInitiated, attributes: .concurrent)
    private let imageSemaphore = DispatchSemaphore(value: max(2, ProcessInfo.processInfo.activeProcessorCount - 2))

    private init() {}

    func clear() {
        cache.removeAllObjects()
    }

    /// The Finder icon for a file — synchronous and cheap.
    func icon(for item: FileItem) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: item.url.path)
        icon.size = NSSize(width: 64, height: 64)
        return icon
    }

    /// `size` is in points; thumbnails are rendered at the screen's backing scale.
    func thumbnail(for item: FileItem, size: CGFloat) async -> NSImage? {
        let key = "\(item.id)#\(Int(size))#\(Int(item.modified.timeIntervalSince1970))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let scale = await MainActor.run { NSScreen.main?.backingScaleFactor ?? 2 }
        let pixels = Int(size * scale)

        var image: NSImage?
        switch item.kind {
        case .image:
            if item.url.pathExtension.lowercased() != "svg" {
                image = await imageIOThumbnail(url: item.url, maxPixels: pixels)
            }
            if image == nil { image = await quickLookThumbnail(url: item.url, size: size, scale: scale) }
        case .video, .pdf:
            image = await quickLookThumbnail(url: item.url, size: size, scale: scale)
        default:
            image = nil
        }
        if Task.isCancelled { return image }

        let result = image ?? icon(for: item)
        let cost = Int(result.size.width * result.size.height * 4 * 2)
        cache.setObject(result, forKey: key, cost: cost)
        return result
    }

    private func imageIOThumbnail(url: URL, maxPixels: Int) async -> NSImage? {
        await withCheckedContinuation { continuation in
            imageQueue.async {
                self.imageSemaphore.wait()
                defer { self.imageSemaphore.signal() }
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
                guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                    continuation.resume(returning: nil)
                    return
                }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels
                ]
                guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                continuation.resume(returning: image)
            }
        }
    }

    private func quickLookThumbnail(url: URL, size: CGFloat, scale: CGFloat) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
        }
    }
}
