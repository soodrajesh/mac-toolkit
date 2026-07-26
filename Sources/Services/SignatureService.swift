import AppKit
import CoreGraphics

/// Builds transparent signature images from drawn strokes or typed text.
enum SignatureService {

    /// Renders drawn strokes (in `size` point space, top-left origin) to a transparent CGImage.
    static func fromStrokes(_ strokes: [[CGPoint]], size: CGSize, color: NSColor, lineWidth: CGFloat = 3,
                            scale: CGFloat = 3) -> CGImage? {
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setStrokeColor((color.usingColorSpace(.deviceRGB) ?? color).cgColor)
        ctx.setLineWidth(lineWidth * scale); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        for stroke in strokes where stroke.count > 1 {
            ctx.beginPath()
            ctx.move(to: CGPoint(x: stroke[0].x * scale, y: (size.height - stroke[0].y) * scale))
            for pt in stroke.dropFirst() {
                ctx.addLine(to: CGPoint(x: pt.x * scale, y: (size.height - pt.y) * scale))
            }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }

    /// Renders typed text (e.g. a script font) to a transparent CGImage sized to the text.
    static func fromText(_ text: String, fontName: String, color: NSColor) -> CGImage? {
        guard !text.isEmpty else { return nil }
        let font = FreeformService.makeFont(fontName, size: 160, bold: false, italic: false)
        let attr = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
        let ts = attr.size()
        let pad: CGFloat = 20
        let w = Int(ceil(ts.width)) + Int(pad * 2), h = Int(ceil(ts.height)) + Int(pad * 2)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = nsCtx
        attr.draw(at: CGPoint(x: pad, y: pad))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
