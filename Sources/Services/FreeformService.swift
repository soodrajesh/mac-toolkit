import AppKit
import CoreGraphics

/// Renders a free-form canvas: images and text placed with independent position,
/// scale, and rotation, composited onto a background at full resolution.
enum FreeformService {

    enum Content {
        case image(CGImage, aspect: CGFloat)
        case text(String, fontName: String, fontFrac: CGFloat, color: NSColor, bold: Bool, italic: Bool)
    }

    struct Item {
        let content: Content
        var center: CGPoint    // normalized 0…1, top-left origin
        var widthFrac: CGFloat // image width as a fraction of canvas width (ignored for text)
        var rotation: CGFloat  // radians, clockwise (screen convention)
        var opacity: CGFloat = 1
    }

    static func render(_ items: [Item], canvasW: Int, canvasH: Int, bg: NSColor) -> CGImage? {
        guard canvasW > 0, canvasH > 0,
              let ctx = CGContext(data: nil, width: canvasW, height: canvasH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor((bg.usingColorSpace(.deviceRGB) ?? bg).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))
        ctx.interpolationQuality = .high

        for it in items {
            let cx = it.center.x * CGFloat(canvasW)
            let cy = CGFloat(canvasH) - it.center.y * CGFloat(canvasH)  // flip to bottom-left origin
            ctx.saveGState()
            ctx.setAlpha(it.opacity)
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -it.rotation)

            switch it.content {
            case .image(let cg, let aspect):
                let w = it.widthFrac * CGFloat(canvasW)
                let h = w * aspect
                ctx.draw(cg, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            case .text(let str, let fontName, let fontFrac, let color, let bold, let italic):
                let font = makeFont(fontName, size: fontFrac * CGFloat(canvasW), bold: bold, italic: italic)
                let attr = NSAttributedString(string: str, attributes: [.font: font, .foregroundColor: color])
                let ts = attr.size()
                let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = nsCtx
                attr.draw(at: CGPoint(x: -ts.width / 2, y: -ts.height / 2))
                NSGraphicsContext.restoreGraphicsState()
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    static func makeFont(_ name: String, size: CGFloat, bold: Bool, italic: Bool) -> NSFont {
        var font = NSFont(name: name, size: size) ?? NSFont.systemFont(ofSize: size)
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }
        if italic { traits.insert(.italicFontMask) }
        if !traits.isEmpty {
            font = NSFontManager.shared.convert(font, toHaveTrait: traits)
        }
        return font
    }
}
