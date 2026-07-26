import AVFoundation
import CoreMedia
import PDFKit
import ImageIO
import AppKit

/// A single labeled metadata row (e.g. "Camera" → "Canon EOS R5").
struct MetadataField: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
    static func == (l: MetadataField, r: MetadataField) -> Bool { l.label == r.label && l.value == r.value }
}

/// Detailed, best-effort metadata for the selected file — dimensions/EXIF for
/// images, document properties for PDFs, codec/bitrate/tags for audio & video —
/// plus video thumbnails for preview panes. Returns [] rather than throwing so
/// callers can show it without extra error handling.
enum FileInfoService {

    // MARK: Images

    static func imageFields(_ url: URL) -> [MetadataField] {
        var f: [MetadataField] = []
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return f }
        if let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int {
            f.append(.init(label: "Dimensions", value: "\(w) × \(h) px"))
        }
        f.append(.init(label: "File size", value: url.fileSize.humanBytes))
        f.append(.init(label: "Format", value: url.pathExtension.uppercased()))
        if let colorModel = props[kCGImagePropertyColorModel] as? String {
            f.append(.init(label: "Color space", value: colorModel))
        }
        if let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 0 {
            f.append(.init(label: "Resolution", value: "\(Int(dpi)) dpi"))
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make = tiff[kCGImagePropertyTIFFMake] as? String
            let model = tiff[kCGImagePropertyTIFFModel] as? String
            let camera = [make, model].compactMap { $0 }.joined(separator: " ")
            if !camera.isEmpty { f.append(.init(label: "Camera", value: camera)) }
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            if let dto = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
                f.append(.init(label: "Date taken", value: dto))
            }
            if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
                f.append(.init(label: "ISO", value: "\(iso)"))
            }
            if let fnum = exif[kCGImagePropertyExifFNumber] as? Double {
                f.append(.init(label: "Aperture", value: String(format: "f/%.1f", fnum)))
            }
            if let exposure = exif[kCGImagePropertyExifExposureTime] as? Double, exposure > 0 {
                f.append(.init(label: "Shutter", value: exposure < 1 ? "1/\(Int((1 / exposure).rounded()))s" : "\(exposure)s"))
            }
            if let focal = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int {
                f.append(.init(label: "Focal length", value: "\(focal)mm"))
            }
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            let latRef = (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" ? -lat : lat
            let lonRef = (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" ? -lon : lon
            f.append(.init(label: "GPS", value: String(format: "%.5f, %.5f", latRef, lonRef)))
        }
        return f
    }

    // MARK: PDF

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium; df.timeStyle = .short
        return df
    }()

    static func pdfFields(_ url: URL) -> [MetadataField] {
        guard let doc = PDFDocument(url: url) else { return [] }
        var f: [MetadataField] = []
        f.append(.init(label: "Pages", value: "\(doc.pageCount)"))
        f.append(.init(label: "File size", value: url.fileSize.humanBytes))
        f.append(.init(label: "Encrypted", value: doc.isEncrypted ? "Yes" : "No"))
        if let page = doc.page(at: 0) {
            let b = page.bounds(for: .mediaBox)
            f.append(.init(label: "Page size", value: "\(Int(b.width)) × \(Int(b.height)) pt"))
        }
        if let attrs = doc.documentAttributes {
            if let v = attrs[PDFDocumentAttribute.titleAttribute] as? String, !v.isEmpty { f.append(.init(label: "Title", value: v)) }
            if let v = attrs[PDFDocumentAttribute.authorAttribute] as? String, !v.isEmpty { f.append(.init(label: "Author", value: v)) }
            if let v = attrs[PDFDocumentAttribute.creatorAttribute] as? String, !v.isEmpty { f.append(.init(label: "Creator", value: v)) }
            if let v = attrs[PDFDocumentAttribute.producerAttribute] as? String, !v.isEmpty { f.append(.init(label: "Producer", value: v)) }
            if let v = attrs[PDFDocumentAttribute.creationDateAttribute] as? Date {
                f.append(.init(label: "Created", value: dateFormatter.string(from: v)))
            }
            if let v = attrs[PDFDocumentAttribute.modificationDateAttribute] as? Date {
                f.append(.init(label: "Modified", value: dateFormatter.string(from: v)))
            }
        }
        return f
    }

    // MARK: Audio

    static func audioFields(_ url: URL) -> [MetadataField] {
        var f: [MetadataField] = []
        let asset = AVURLAsset(url: url)
        let dur = CMTimeGetSeconds(asset.duration)
        if dur.isFinite, dur > 0 { f.append(.init(label: "Duration", value: formatDuration(dur))) }
        f.append(.init(label: "File size", value: url.fileSize.humanBytes))
        if let track = asset.tracks(withMediaType: .audio).first {
            if let desc = track.formatDescriptions.first {
                let fd = desc as! CMFormatDescription
                f.append(.init(label: "Codec", value: codecName(CMFormatDescriptionGetMediaSubType(fd))))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                    f.append(.init(label: "Sample rate", value: "\(Int(asbd.mSampleRate)) Hz"))
                    f.append(.init(label: "Channels", value: "\(asbd.mChannelsPerFrame)"))
                }
            }
            if track.estimatedDataRate > 0 {
                f.append(.init(label: "Bitrate", value: "\(Int(track.estimatedDataRate / 1000)) kbps"))
            }
        }
        for item in AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierTitle) {
            if let v = item.stringValue, !v.isEmpty { f.append(.init(label: "Title", value: v)) }
        }
        for item in AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierArtist) {
            if let v = item.stringValue, !v.isEmpty { f.append(.init(label: "Artist", value: v)) }
        }
        for item in AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: .commonIdentifierAlbumName) {
            if let v = item.stringValue, !v.isEmpty { f.append(.init(label: "Album", value: v)) }
        }
        return f
    }

    // MARK: Video

    static func videoFields(_ url: URL) -> [MetadataField] {
        var f: [MetadataField] = []
        let asset = AVURLAsset(url: url)
        if let track = asset.tracks(withMediaType: .video).first {
            let size = track.naturalSize.applying(track.preferredTransform)
            f.append(.init(label: "Resolution", value: "\(Int(abs(size.width))) × \(Int(abs(size.height)))"))
            if track.nominalFrameRate > 0 {
                f.append(.init(label: "Frame rate", value: String(format: "%.2f fps", track.nominalFrameRate)))
            }
            if let desc = track.formatDescriptions.first {
                let fd = desc as! CMFormatDescription
                f.append(.init(label: "Video codec", value: codecName(CMFormatDescriptionGetMediaSubType(fd))))
            }
            if track.estimatedDataRate > 0 {
                f.append(.init(label: "Video bitrate", value: "\(Int(track.estimatedDataRate / 1000)) kbps"))
            }
        }
        let dur = CMTimeGetSeconds(asset.duration)
        if dur.isFinite, dur > 0 { f.append(.init(label: "Duration", value: formatDuration(dur))) }
        f.append(.init(label: "File size", value: url.fileSize.humanBytes))
        if let audioTrack = asset.tracks(withMediaType: .audio).first {
            if let desc = audioTrack.formatDescriptions.first {
                let fd = desc as! CMFormatDescription
                f.append(.init(label: "Audio codec", value: codecName(CMFormatDescriptionGetMediaSubType(fd))))
                if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fd)?.pointee {
                    f.append(.init(label: "Audio channels", value: "\(asbd.mChannelsPerFrame)"))
                }
            }
        }
        return f
    }

    /// Maps a Core Media FourCC to a human-readable codec name. Falls back to
    /// the raw four-character code for anything not explicitly known.
    private static func codecName(_ code: FourCharCode) -> String {
        switch code {
        case kCMVideoCodecType_H264: return "H.264"
        case kCMVideoCodecType_HEVC: return "HEVC"
        case kCMVideoCodecType_JPEG: return "Motion JPEG"
        case kCMVideoCodecType_AppleProRes422: return "ProRes 422"
        case kCMVideoCodecType_AppleProRes4444: return "ProRes 4444"
        case kAudioFormatMPEG4AAC: return "AAC"
        case kAudioFormatMPEGLayer3: return "MP3"
        case kAudioFormatAppleLossless: return "ALAC"
        case kAudioFormatLinearPCM: return "PCM"
        case kAudioFormatOpus: return "Opus"
        default: break
        }
        let bytes = [UInt8(code >> 24 & 0xff), UInt8(code >> 16 & 0xff), UInt8(code >> 8 & 0xff), UInt8(code & 0xff)]
        let str = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch str.lowercased() {
        case "vp09", "vp9", "vp08", "vp8": return str.count == 4 ? "VP\(str.suffix(1))" : str.uppercased()
        case "av01": return "AV1"
        case "avc1": return "H.264"
        case "hvc1", "hev1": return "HEVC"
        case "mp4a": return "AAC"
        case "fl ac", "flac": return "FLAC"
        default: return str.isEmpty ? "Unknown" : str
        }
    }

    /// A thumbnail frame from partway into the video, for preview panes.
    /// Falls back to ffmpeg (if installed) for codecs AVFoundation can't
    /// decode, e.g. VP9/AV1 from a high-res YouTube download.
    static func videoThumbnail(_ url: URL, maxSize: CGFloat = 480) -> NSImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: maxSize, height: maxSize)
        let time = CMTime(seconds: min(1, CMTimeGetSeconds(asset.duration) / 2), preferredTimescale: 600)
        if let cg = try? gen.copyCGImage(at: time, actualTime: nil) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        guard let ffmpeg = YtDlp.ffmpegPath else { return nil }
        let out = OutputPath.temp(ext: "jpg")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-y", "-ss", "1", "-i", url.path, "-frames:v", "1", "-vf", "scale=\(Int(maxSize)):-2", out.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        defer { try? FileManager.default.removeItem(at: out) }
        guard p.terminationStatus == 0 else { return nil }
        return NSImage(contentsOf: out)
    }

    static func formatDuration(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }
}
