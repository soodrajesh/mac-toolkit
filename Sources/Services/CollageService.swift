import AppKit
import CoreGraphics

/// Combines multiple images into one — grid, horizontal strip, or vertical strip.
enum CollageService {
    enum Layout: String, CaseIterable, Identifiable {
        case grid = "Grid"
        case horizontal = "Horizontal"
        case vertical = "Vertical"
        case freeform = "Freeform"
        var id: String { rawValue }
    }

    /// Each image is aspect-fit into a square `cell`; `spacing` px gutters on a `bg` canvas.
    static func combine(_ urls: [URL], layout: Layout, columns: Int, cell: Int,
                        spacing: Int, bg: NSColor) throws -> CGImage {
        let imgs = urls.compactMap { try? ImageService.loadCGImage($0) }
        guard !imgs.isEmpty else { throw JobError.badInput("No readable images") }

        let cols: Int
        switch layout {
        case .horizontal: cols = imgs.count
        case .vertical:   cols = 1
        case .grid, .freeform: cols = max(1, min(columns, imgs.count))
        }
        let rows = Int(ceil(Double(imgs.count) / Double(cols)))

        let W = cols * cell + (cols + 1) * spacing
        let H = rows * cell + (rows + 1) * spacing
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw JobError.failed("Could not create canvas")
        }
        ctx.setFillColor(bg.usingColorSpace(.deviceRGB)?.cgColor ?? NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.interpolationQuality = .high

        for (i, img) in imgs.enumerated() {
            let col = i % cols, row = i / cols
            let x = spacing + col * (cell + spacing)
            let yTop = spacing + row * (cell + spacing)
            let yBottom = H - yTop - cell     // flip to bottom-left origin
            let cellRect = CGRect(x: x, y: yBottom, width: cell, height: cell)
            ctx.draw(img, in: aspectFit(CGSize(width: img.width, height: img.height), into: cellRect))
        }
        guard let out = ctx.makeImage() else { throw JobError.failed("Render failed") }
        return out
    }

    private static func aspectFit(_ size: CGSize, into rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
