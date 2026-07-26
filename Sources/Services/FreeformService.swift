import AppKit
import CoreGraphics

/// Renders a free-form canvas: images placed with independent position, scale,
/// and rotation, composited onto a background at full resolution.
enum FreeformService {

    struct Item {
        let cg: CGImage
        var center: CGPoint    // normalized 0…1, top-left origin
        var widthFrac: CGFloat // item width as a fraction of canvas width
        var rotation: CGFloat  // radians, clockwise (screen convention)
        var aspect: CGFloat    // height / width of the source image
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
            let w = it.widthFrac * CGFloat(canvasW)
            let h = w * it.aspect
            let cx = it.center.x * CGFloat(canvasW)
            let cy = CGFloat(canvasH) - it.center.y * CGFloat(canvasH)  // flip to bottom-left origin
            ctx.saveGState()
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -it.rotation)   // screen is y-down clockwise; context is y-up
            ctx.draw(it.cg, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }
}
