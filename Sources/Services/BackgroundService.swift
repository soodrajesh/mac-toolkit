import Vision
import CoreImage
import CoreGraphics
import AppKit
import Foundation

/// Subject cutout via Vision, plus optional background replacement.
enum BackgroundService {

    enum Background {
        case transparent
        case color(NSColor)
        case image(CGImage)
    }

    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true } else { return false }
    }

    /// Returns the foreground subject as a transparent-background CGImage.
    static func cutout(_ url: URL) throws -> CGImage {
        try cutout(try ImageService.loadCGImage(url))
    }

    /// Same as `cutout(_ url:)`, but runs directly on an in-memory image —
    /// e.g. a user-cropped region, which gives Vision a tighter, less
    /// ambiguous frame and often yields a cleaner mask.
    static func cutout(_ img: CGImage) throws -> CGImage {
        guard #available(macOS 14.0, *) else {
            throw JobError.failed("Background removal needs macOS 14 or later")
        }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try handler.perform([request])
        guard let result = request.results?.first else {
            throw JobError.failed("No subject detected in image")
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else {
            throw JobError.failed("Could not render cutout")
        }
        return cg
    }

    /// Composites a transparent cutout onto the chosen background.
    static func composite(_ cutout: CGImage, background: Background) -> CGImage {
        if case .transparent = background { return cutout }
        let w = cutout.width, h = cutout.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cutout }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.interpolationQuality = .high
        switch background {
        case .transparent: break
        case .color(let c):
            ctx.setFillColor((c.usingColorSpace(.deviceRGB) ?? c).cgColor); ctx.fill(rect)
        case .image(let bg):
            let scale = max(CGFloat(w) / CGFloat(bg.width), CGFloat(h) / CGFloat(bg.height))
            let bw = CGFloat(bg.width) * scale, bh = CGFloat(bg.height) * scale
            ctx.draw(bg, in: CGRect(x: (CGFloat(w) - bw) / 2, y: (CGFloat(h) - bh) / 2, width: bw, height: bh))
        }
        ctx.draw(cutout, in: rect)
        return ctx.makeImage() ?? cutout
    }
}
