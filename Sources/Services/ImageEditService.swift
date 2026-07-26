import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins

/// Pixel-level image edits: rotate, flip, crop, resize, redact, blur/pixelate.
/// All rects are normalized (0…1, top-left origin) to match RegionSelector.
enum ImageEditService {

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    static func rotate(_ cg: CGImage, quarters: Int) -> CGImage? {
        let q = ((quarters % 4) + 4) % 4
        if q == 0 { return cg }
        let w = cg.width, h = cg.height
        let swapped = q % 2 == 1
        let nw = swapped ? h : w, nh = swapped ? w : h
        guard let ctx = context(nw, nh) else { return nil }
        ctx.translateBy(x: CGFloat(nw) / 2, y: CGFloat(nh) / 2)
        ctx.rotate(by: -CGFloat(q) * .pi / 2)   // clockwise per 90°
        ctx.translateBy(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func flip(_ cg: CGImage, horizontal: Bool, vertical: Bool) -> CGImage? {
        guard horizontal || vertical else { return cg }
        let w = cg.width, h = cg.height
        guard let ctx = context(w, h) else { return nil }
        ctx.translateBy(x: horizontal ? CGFloat(w) : 0, y: vertical ? CGFloat(h) : 0)
        ctx.scaleBy(x: horizontal ? -1 : 1, y: vertical ? -1 : 1)
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Crops to a normalized top-left rect. (CGImage cropping uses top-left pixel origin.)
    static func crop(_ cg: CGImage, normRect r: CGRect) -> CGImage? {
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let rect = CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H).integral
        guard rect.width >= 1, rect.height >= 1 else { return cg }
        return cg.cropping(to: rect)
    }

    /// Fits within (maxW, maxH) preserving aspect ratio.
    static func resizeFit(_ cg: CGImage, maxW: Int, maxH: Int) -> CGImage? {
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(CGFloat(maxW) / w, CGFloat(maxH) / h)
        let nw = max(1, Int((w * scale).rounded())), nh = max(1, Int((h * scale).rounded()))
        guard let ctx = context(nw, nh) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        return ctx.makeImage()
    }

    /// Paints solid black over normalized rects — pixels are destroyed (true redaction).
    static func redact(_ cg: CGImage, rects: [CGRect]) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(NSColor.black.cgColor)
        for r in rects { ctx.fill(pixelRect(r, w, h)) }
        return ctx.makeImage()
    }

    /// Blurs or pixelates normalized rects, compositing back over the original.
    static func obscure(_ cg: CGImage, rects: [CGRect], pixelate: Bool, intensity: Double) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let ci = CIImage(cgImage: cg)
        let ciCtx = CIContext()
        for r in rects {
            let region = pixelRect(r, w, h)
            guard region.width >= 2, region.height >= 2 else { continue }
            let processed: CIImage
            if pixelate {
                let f = CIFilter.pixellate()
                f.inputImage = ci.clampedToExtent()
                f.center = CGPoint(x: region.midX, y: region.midY)
                f.scale = Float(max(4, intensity))
                processed = (f.outputImage ?? ci).cropped(to: region)
            } else {
                let f = CIFilter.gaussianBlur()
                f.inputImage = ci.clampedToExtent()
                f.radius = Float(max(2, intensity))
                processed = (f.outputImage ?? ci).cropped(to: region)
            }
            if let outCG = ciCtx.createCGImage(processed, from: region) {
                ctx.draw(outCG, in: region)
            }
        }
        return ctx.makeImage()
    }

    /// Normalized top-left rect → pixel rect in CGContext (bottom-left origin) space.
    private static func pixelRect(_ r: CGRect, _ w: Int, _ h: Int) -> CGRect {
        let W = CGFloat(w), H = CGFloat(h)
        let rw = r.width * W, rh = r.height * H
        let x = r.minX * W
        let y = H - (r.minY * H) - rh
        return CGRect(x: x, y: y, width: rw, height: rh).integral
    }
}

/// Named resize targets (fit-within, aspect preserved).
enum ResizePreset: String, CaseIterable, Identifiable {
    case none = "Original size"
    case avatar = "Avatar (400×400)"
    case igSquare = "Instagram square (1080)"
    case igPortrait = "Instagram portrait (1080×1350)"
    case linkedInBanner = "LinkedIn banner (1584×396)"
    case fullHD = "Full HD (1920)"
    case uhd4k = "4K (3840)"
    var id: String { rawValue }
    var box: (Int, Int)? {
        switch self {
        case .none: return nil
        case .avatar: return (400, 400)
        case .igSquare: return (1080, 1080)
        case .igPortrait: return (1080, 1350)
        case .linkedInBanner: return (1584, 396)
        case .fullHD: return (1920, 1920)
        case .uhd4k: return (3840, 3840)
        }
    }
}
