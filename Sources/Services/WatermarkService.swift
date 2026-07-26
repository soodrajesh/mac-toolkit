import AppKit
import CoreGraphics

/// Batch watermarking: text or a logo image, placed at a corner/center or tiled.
enum WatermarkService {
    enum Placement: String, CaseIterable, Identifiable {
        case topLeft = "Top left", topCenter = "Top center", topRight = "Top right"
        case center = "Center"
        case bottomLeft = "Bottom left", bottomCenter = "Bottom center", bottomRight = "Bottom right"
        case tiled = "Tiled"
        var id: String { rawValue }
    }

    static func applyText(_ cg: CGImage, text: String, fontName: String, fontFrac: Double,
                          color: NSColor, opacity: Double, placement: Placement) -> CGImage? {
        guard !text.isEmpty else { return cg }
        let w = cg.width, h = cg.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let font = FreeformService.makeFont(fontName, size: CGFloat(fontFrac) * CGFloat(w), bold: false, italic: false)
        let attr = NSAttributedString(string: text,
            attributes: [.font: font, .foregroundColor: color.withAlphaComponent(CGFloat(opacity))])
        drawText(attr, size: attr.size(), in: ctx, w: w, h: h, placement: placement)
        return ctx.makeImage()
    }

    static func applyImage(_ cg: CGImage, logo: CGImage, widthFrac: Double, opacity: Double, placement: Placement) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = context(w, h) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        let lw = CGFloat(widthFrac) * CGFloat(w)
        let lh = lw * CGFloat(logo.height) / CGFloat(logo.width)
        ctx.setAlpha(CGFloat(opacity))
        for p in positions(for: CGSize(width: lw, height: lh), w: w, h: h, placement: placement) {
            ctx.draw(logo, in: CGRect(origin: p, size: CGSize(width: lw, height: lh)))
        }
        return ctx.makeImage()
    }

    private static func context(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }

    private static func positions(for size: CGSize, w: Int, h: Int, placement: Placement) -> [CGPoint] {
        let m = CGFloat(w) * 0.03
        switch placement {
        case .topLeft:      return [CGPoint(x: m, y: CGFloat(h) - size.height - m)]
        case .topCenter:    return [CGPoint(x: (CGFloat(w) - size.width) / 2, y: CGFloat(h) - size.height - m)]
        case .topRight:     return [CGPoint(x: CGFloat(w) - size.width - m, y: CGFloat(h) - size.height - m)]
        case .center:       return [CGPoint(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2)]
        case .bottomLeft:   return [CGPoint(x: m, y: m)]
        case .bottomCenter: return [CGPoint(x: (CGFloat(w) - size.width) / 2, y: m)]
        case .bottomRight:  return [CGPoint(x: CGFloat(w) - size.width - m, y: m)]
        case .tiled:
            guard size.width > 0, size.height > 0 else { return [] }
            let stepX = size.width * 1.8, stepY = size.height * 2.5
            var pts: [CGPoint] = []
            var y = m
            while y < CGFloat(h) {
                var x = m
                while x < CGFloat(w) { pts.append(CGPoint(x: x, y: y)); x += stepX }
                y += stepY
            }
            return pts
        }
    }

    private static func drawText(_ attr: NSAttributedString, size: CGSize, in ctx: CGContext,
                                 w: Int, h: Int, placement: Placement) {
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = nsCtx
        for p in positions(for: size, w: w, h: h, placement: placement) { attr.draw(at: p) }
        NSGraphicsContext.restoreGraphicsState()
    }
}
