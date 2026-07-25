import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Foundation

/// Generates favicon/app-icon sets from a single source image.
enum IconService {
    static let pngSizes = [16, 32, 48, 64, 128, 180, 192, 256, 512, 1024]
    static let icoSizes = [16, 32, 48, 64, 128, 256]
    static let icnsSizes = [16, 32, 64, 128, 256, 512, 1024]

    /// Center-crops to a square using the smaller side.
    static func square(_ img: CGImage) -> CGImage {
        let side = min(img.width, img.height)
        let x = (img.width - side) / 2
        let y = (img.height - side) / 2
        return img.cropping(to: CGRect(x: x, y: y, width: side, height: side)) ?? img
    }

    static func scaled(_ img: CGImage, to size: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    /// Writes multiple images into one container (ICO/ICNS).
    private static func writeMulti(_ images: [CGImage], to url: URL, type: UTType) throws {
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, type.identifier as CFString, images.count, nil) else {
            throw JobError.cannotWrite(url)
        }
        for img in images { CGImageDestinationAddImage(dest, img, nil) }
        guard CGImageDestinationFinalize(dest) else { throw JobError.cannotWrite(url) }
    }

    /// Produces a `<name>-icons/` folder with PNGs, favicon.ico, and AppIcon.icns.
    /// Returns the created file URLs.
    static func generate(_ source: URL, dir: URL?, makeICO: Bool, makeICNS: Bool,
                         makePNGs: Bool) throws -> [URL] {
        let base = source.deletingPathExtension().lastPathComponent
        let folder = (dir ?? source.deletingLastPathComponent())
            .appendingPathComponent("\(base)-icons", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sq = square(try ImageService.loadCGImage(source))
        var outputs: [URL] = []

        if makePNGs {
            for size in pngSizes {
                guard let scaled = scaled(sq, to: size) else { continue }
                let out = folder.appendingPathComponent("icon-\(size).png")
                try ImageService.write(scaled, to: out, format: .png, quality: 1)
                outputs.append(out)
            }
        }
        if makeICO {
            let imgs = icoSizes.compactMap { scaled(sq, to: $0) }
            let out = folder.appendingPathComponent("favicon.ico")
            try writeMulti(imgs, to: out, type: .ico)
            outputs.append(out)
        }
        if makeICNS {
            let imgs = icnsSizes.compactMap { scaled(sq, to: $0) }
            let out = folder.appendingPathComponent("AppIcon.icns")
            try writeMulti(imgs, to: out, type: UTType("com.apple.icns") ?? .png)
            outputs.append(out)
        }
        return outputs
    }
}
