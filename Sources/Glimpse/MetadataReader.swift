import Foundation
import ImageIO
import CoreGraphics
import AVFoundation
import UniformTypeIdentifiers

/// Reads dimensions, camera data and media info for a single file.
/// Everything here runs off the main thread and never decodes full image pixels.
enum MetadataReader {

    static func read(_ item: FileItem, computeFolderSize: Bool) async -> MediaMeta {
        switch item.kind {
        case .folder:
            return folderMeta(item.url, computeSize: computeFolderSize)
        case .image:
            if item.url.pathExtension.lowercased() == "svg" { return svgMeta(item.url) }
            return imageMeta(item.url)
        case .video:
            return await avMeta(item.url, isVideo: true)
        case .audio:
            return await avMeta(item.url, isVideo: false)
        case .pdf:
            return pdfMeta(item.url)
        case .other:
            return MediaMeta()
        }
    }

    // MARK: - Images (ImageIO: reads headers/EXIF only, no pixel decode)

    private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()

    static func imageMeta(_ url: URL) -> MediaMeta {
        var m = MediaMeta()
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            m.error = "Unreadable image"
            return m
        }
        let count = CGImageSourceGetCount(source)
        if count > 1 { m.frameCount = count }

        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any] else {
            m.error = "No image properties"
            return m
        }

        let rawWidth = intValue(props[kCGImagePropertyPixelWidth])
        let rawHeight = intValue(props[kCGImagePropertyPixelHeight])
        m.orientation = intValue(props[kCGImagePropertyOrientation])
        // Orientations 5–8 are rotated 90°; report the dimensions as the image is displayed.
        if let o = m.orientation, (5...8).contains(o) {
            m.width = rawHeight
            m.height = rawWidth
        } else {
            m.width = rawWidth
            m.height = rawHeight
        }

        m.dpi = doubleValue(props[kCGImagePropertyDPIWidth])
        m.colorModel = props[kCGImagePropertyColorModel] as? String
        m.depth = intValue(props[kCGImagePropertyDepth])
        m.hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool
        m.profile = props[kCGImagePropertyProfileName] as? String

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.make = tiff[kCGImagePropertyTIFFMake] as? String
            m.model = tiff[kCGImagePropertyTIFFModel] as? String
            m.software = tiff[kCGImagePropertyTIFFSoftware] as? String
            if m.dpi == nil { m.dpi = doubleValue(tiff[kCGImagePropertyTIFFXResolution]) }
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let isoArray = exif[kCGImagePropertyExifISOSpeedRatings] as? [Any], let first = isoArray.first {
                m.iso = intValue(first)
            } else {
                m.iso = intValue(exif[kCGImagePropertyExifISOSpeedRatings])
            }
            m.fNumber = doubleValue(exif[kCGImagePropertyExifFNumber])
            m.exposure = doubleValue(exif[kCGImagePropertyExifExposureTime])
            m.focalLength = doubleValue(exif[kCGImagePropertyExifFocalLength])
            m.focalLength35 = intValue(exif[kCGImagePropertyExifFocalLenIn35mmFilm])
            if let lens = exif[kCGImagePropertyExifLensModel] as? String, !lens.isEmpty {
                m.lens = lens
            }
            if let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                m.dateTaken = exifDateFormatter.date(from: dateString)
            }
            if m.dateTaken == nil, let dateString = exif[kCGImagePropertyExifDateTimeDigitized] as? String {
                m.dateTaken = exifDateFormatter.date(from: dateString)
            }
        }

        if m.lens == nil, let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] {
            m.lens = aux[kCGImagePropertyExifAuxLensModel] as? String
        }

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = doubleValue(gps[kCGImagePropertyGPSLatitude]),
           var lon = doubleValue(gps[kCGImagePropertyGPSLongitude]) {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            m.gps = GPSCoordinate(latitude: lat, longitude: lon)
        }

        return m
    }

    // MARK: - SVG (text parse of the root <svg> element)

    static func svgMeta(_ url: URL) -> MediaMeta {
        var m = MediaMeta()
        guard let handle = try? FileHandle(forReadingFrom: url) else { return m }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 64 * 1024)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return m }
        guard let svgStart = text.range(of: "<svg", options: .caseInsensitive) else { return m }
        let tagEnd = text.range(of: ">", range: svgStart.upperBound..<text.endIndex)?.lowerBound ?? text.endIndex
        let tag = String(text[svgStart.lowerBound..<tagEnd])

        func attr(_ name: String) -> String? {
            let pattern = "\\s\(name)\\s*=\\s*[\"']([^\"']+)[\"']"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let ns = tag as NSString
            guard let match = regex.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
            return ns.substring(with: match.range(at: 1))
        }

        func numeric(_ s: String?) -> Double? {
            guard let s else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespaces)
            let digits = trimmed.prefix { "0123456789.-".contains($0) }
            return Double(digits)
        }

        var w = numeric(attr("width"))
        var h = numeric(attr("height"))
        if let unitString = attr("width"), unitString.lowercased().hasSuffix("%") { w = nil }
        if let unitString = attr("height"), unitString.lowercased().hasSuffix("%") { h = nil }

        if w == nil || h == nil, let viewBox = attr("viewBox") {
            let parts = viewBox.replacingOccurrences(of: ",", with: " ")
                .split(separator: " ").compactMap { Double($0) }
            if parts.count == 4 {
                if w == nil { w = parts[2] }
                if h == nil { h = parts[3] }
            }
        }
        if let w, let h {
            m.width = Int(w.rounded())
            m.height = Int(h.rounded())
        }
        m.colorModel = "Vector"
        return m
    }

    // MARK: - PDF

    static func pdfMeta(_ url: URL) -> MediaMeta {
        var m = MediaMeta()
        guard let doc = CGPDFDocument(url as CFURL) else {
            m.error = "Unreadable PDF"
            return m
        }
        m.pageCount = doc.numberOfPages
        if let page = doc.page(at: 1) {
            var rect = page.getBoxRect(.mediaBox)
            let rotation = page.rotationAngle
            if rotation == 90 || rotation == 270 {
                rect = CGRect(x: 0, y: 0, width: rect.height, height: rect.width)
            }
            m.pageSize = rect.size
        }
        return m
    }

    // MARK: - Video & audio (AVFoundation)

    static func avMeta(_ url: URL, isVideo: Bool) async -> MediaMeta {
        var m = MediaMeta()
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            if seconds.isFinite { m.duration = seconds }

            if isVideo {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                if let track = videoTracks.first {
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let rect = CGRect(origin: .zero, size: size).applying(transform)
                    m.width = Int(abs(rect.width).rounded())
                    m.height = Int(abs(rect.height).rounded())

                    let fps = try await track.load(.nominalFrameRate)
                    if fps > 0 { m.fps = Double(fps) }

                    let rate = try await track.load(.estimatedDataRate)
                    if rate > 0 { m.bitrate = Double(rate) }

                    let descriptions = try await track.load(.formatDescriptions)
                    if let desc = descriptions.first {
                        m.codec = codecName(CMFormatDescriptionGetMediaSubType(desc))
                    }
                }
            }

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            if let track = audioTracks.first {
                let descriptions = try await track.load(.formatDescriptions)
                if let desc = descriptions.first {
                    m.audioCodec = codecName(CMFormatDescriptionGetMediaSubType(desc))
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc) {
                        m.sampleRate = asbd.pointee.mSampleRate
                        m.channels = Int(asbd.pointee.mChannelsPerFrame)
                    }
                }
                if !isVideo {
                    let rate = try await track.load(.estimatedDataRate)
                    if rate > 0 { m.bitrate = Double(rate) }
                }
            }

            // Camera make / model / creation date, when the recorder wrote them.
            let metadata = try await asset.load(.metadata)
            for item in metadata {
                let identifier = item.identifier
                let commonKey = item.commonKey
                if identifier == .quickTimeMetadataMake || commonKey == .commonKeyMake {
                    m.make = try? await item.load(.stringValue)
                } else if identifier == .quickTimeMetadataModel || commonKey == .commonKeyModel {
                    m.model = try? await item.load(.stringValue)
                } else if identifier == .quickTimeMetadataSoftware || commonKey == .commonKeySoftware {
                    m.software = try? await item.load(.stringValue)
                } else if identifier == .quickTimeMetadataLocationISO6709 || commonKey == .commonKeyLocation {
                    if let s = try? await item.load(.stringValue), let gps = parseISO6709(s) {
                        m.gps = gps
                    }
                }
            }
            if let creation = try await asset.load(.creationDate) {
                m.dateTaken = try? await creation.load(.dateValue)
            }
        } catch {
            m.error = error.localizedDescription
        }
        return m
    }

    /// Parses "+12.3456-078.9012+000.000/" style strings written by phones.
    private static func parseISO6709(_ s: String) -> GPSCoordinate? {
        let pattern = "([+-][0-9.]+)([+-][0-9.]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = s as NSString
        guard let match = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        guard let lat = Double(ns.substring(with: match.range(at: 1))),
              let lon = Double(ns.substring(with: match.range(at: 2))) else { return nil }
        return GPSCoordinate(latitude: lat, longitude: lon)
    }

    private static func codecName(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff), UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff), UInt8(code & 0xff)
        ]
        let raw = String(bytes: bytes, encoding: .macOSRoman)?.trimmingCharacters(in: .whitespaces) ?? "?"
        switch raw {
        case "avc1", "avc3": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "ap4h": return "ProRes 4444"
        case "ap4x": return "ProRes 4444 XQ"
        case "apch": return "ProRes 422 HQ"
        case "apcn": return "ProRes 422"
        case "apcs": return "ProRes 422 LT"
        case "apco": return "ProRes 422 Proxy"
        case "aprn", "aprh": return "ProRes RAW"
        case "mp4v": return "MPEG-4"
        case "jpeg": return "Motion JPEG"
        case "av01": return "AV1"
        case "vp09": return "VP9"
        case "vp08": return "VP8"
        case "dvh1", "dvhe": return "Dolby Vision"
        case "aac ", "aac": return "AAC"
        case "mp4a": return "AAC"
        case "lpcm": return "PCM"
        case "alac": return "ALAC"
        case ".mp3": return "MP3"
        case "ac-3": return "AC-3"
        case "ec-3": return "E-AC-3"
        case "flac": return "FLAC"
        case "Opus", "opus": return "Opus"
        default: return raw.uppercased()
        }
    }

    // MARK: - Folders

    static func folderMeta(_ url: URL, computeSize: Bool) -> MediaMeta {
        var m = MediaMeta()
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            m.itemCount = contents.count
        }
        guard computeSize else { return m }

        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) {
            var counter = 0
            for case let fileURL as URL in enumerator {
                counter += 1
                if counter % 200 == 0, Task.isCancelled { return m }
                guard let values = try? fileURL.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? 0)
            }
        }
        m.folderSize = total
        return m
    }

    // MARK: - Helpers

    private static func intValue(_ any: Any?) -> Int? {
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }
}
