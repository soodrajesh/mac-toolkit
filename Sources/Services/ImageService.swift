import AppKit
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// Image encode/convert/resize via ImageIO. No third-party deps.
enum ImageService {

    enum Format: String, CaseIterable, Identifiable {
        case jpeg, png, heic, tiff
        var id: String { rawValue }
        var utType: UTType {
            switch self {
            case .jpeg: return .jpeg
            case .png:  return .png
            case .heic: return .heic
            case .tiff: return .tiff
            }
        }
        var ext: String { self == .jpeg ? "jpg" : rawValue }
        var lossy: Bool { self == .jpeg || self == .heic }
        var label: String { rawValue.uppercased() }
    }

    /// Loads the first image in a file as a CGImage.
    static func loadCGImage(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            throw JobError.cannotOpen(url)
        }
        return img
    }

    /// Loads a downsampled CGImage whose largest side is <= maxPixel (if given).
    static func loadDownsampled(_ url: URL, maxPixel: Int?) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw JobError.cannotOpen(url)
        }
        guard let maxPixel else {
            guard let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
                throw JobError.cannotOpen(url)
            }
            return img
        }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
            throw JobError.cannotOpen(url)
        }
        return img
    }

    /// Encodes a CGImage to disk. `quality` (0–1) applies to lossy formats.
    /// Metadata is never copied from the source, so EXIF/GPS is stripped.
    static func write(_ image: CGImage, to url: URL, format: Format, quality: Double) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw JobError.cannotWrite(url)
        }
        var props: [CFString: Any] = [:]
        if format.lossy {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw JobError.cannotWrite(url) }
    }

    /// Encodes to in-memory Data — used to estimate output file size.
    static func encodeData(_ image: CGImage, format: Format, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [:]
        if format.lossy { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// One-stop transform: optional downscale + format + quality.
    /// Returns (output URL, before, after) sizes.
    static func process(_ url: URL,
                        format: Format,
                        quality: Double,
                        maxPixel: Int?,
                        dir: URL?,
                        suffix: String) throws -> (out: URL, before: Int64, after: Int64) {
        let before = url.fileSize
        let img = try loadDownsampled(url, maxPixel: maxPixel)
        let out = OutputPath.make(for: url, dir: dir, suffix: suffix, ext: format.ext)
        try write(img, to: out, format: format, quality: quality)
        return (out, before, out.fileSize)
    }
}
