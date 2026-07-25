import AppKit
import Vision
import PDFKit
import CoreGraphics
import CoreText

/// Text recognition via the Vision framework.
enum OCRService {

    /// Recognizes text in a single CGImage. Returns joined lines.
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else { return "" }
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }

    /// OCRs an image file.
    static func recognizeImageFile(_ url: URL) throws -> String {
        let img = try ImageService.loadCGImage(url)
        return try recognize(img)
    }

    /// OCRs every page of a PDF (rendered at `dpi`) and concatenates.
    static func recognizePDF(_ url: URL, dpi: Double = 200) throws -> String {
        let doc = try PDFService.open(url)
        var chunks: [String] = []
        let scale = dpi / 72.0
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let w = Int((bounds.width * scale).rounded())
            let h = Int((bounds.height * scale).rounded())
            guard w > 0, h > 0,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                continue
            }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)
            guard let cg = ctx.makeImage() else { continue }
            let text = try recognize(cg)
            chunks.append("--- Page \(p + 1) ---\n\(text)")
        }
        return chunks.joined(separator: "\n\n")
    }

    // MARK: Searchable PDF

    private struct RenderedPage { let image: CGImage; let rect: CGRect }

    /// Builds a searchable PDF: each page is the source image with an invisible,
    /// selectable text layer positioned over the recognized words.
    static func makeSearchablePDF(_ url: URL, to output: URL, dpi: Double = 200) throws {
        let rendered = try renderPages(url, dpi: dpi)
        guard !rendered.isEmpty else { throw JobError.failed("Nothing to process") }
        guard let consumer = CGDataConsumer(url: output as CFURL) else {
            throw JobError.cannotWrite(output)
        }
        var mediaBox = rendered[0].rect
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw JobError.cannotWrite(output)
        }
        for page in rendered {
            var box = page.rect
            ctx.beginPage(mediaBox: &box)
            ctx.draw(page.image, in: page.rect)

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: page.image, options: [:])
            try? handler.perform([request])

            for obs in request.results ?? [] {
                guard let cand = obs.topCandidates(1).first else { continue }
                let bb = obs.boundingBox  // normalized, origin bottom-left → matches PDF space
                let rect = CGRect(x: bb.minX * page.rect.width,
                                  y: bb.minY * page.rect.height,
                                  width: bb.width * page.rect.width,
                                  height: bb.height * page.rect.height)
                drawInvisibleText(cand.string, in: rect, ctx: ctx)
            }
            ctx.endPage()
        }
        ctx.closePDF()
    }

    private static func renderPages(_ url: URL, dpi: Double) throws -> [RenderedPage] {
        if url.conformsTo(.pdf) {
            let doc = try PDFService.open(url)
            var out: [RenderedPage] = []
            let scale = dpi / 72.0
            for p in 0..<doc.pageCount {
                guard let page = doc.page(at: p) else { continue }
                let bounds = page.bounds(for: .mediaBox)
                let w = Int((bounds.width * scale).rounded())
                let h = Int((bounds.height * scale).rounded())
                guard w > 0, h > 0,
                      let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
                    continue
                }
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
                ctx.scaleBy(x: scale, y: scale)
                ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
                page.draw(with: .mediaBox, to: ctx)
                guard let cg = ctx.makeImage() else { continue }
                out.append(RenderedPage(image: cg, rect: CGRect(origin: .zero, size: bounds.size)))
            }
            return out
        } else {
            let img = try ImageService.loadCGImage(url)
            let rect = CGRect(x: 0, y: 0, width: img.width, height: img.height)
            return [RenderedPage(image: img, rect: rect)]
        }
    }

    /// Draws text in invisible render mode (PDF text mode 3): selectable but unseen.
    private static func drawInvisibleText(_ text: String, in rect: CGRect, ctx: CGContext) {
        guard !text.isEmpty, rect.height > 1, rect.width > 1 else { return }
        let fontSize = rect.height * 0.8
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attr = NSAttributedString(string: text, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let scaleX = lineWidth > 0 ? rect.width / CGFloat(lineWidth) : 1

        ctx.saveGState()
        ctx.setTextDrawingMode(.invisible)
        ctx.textMatrix = CGAffineTransform(scaleX: scaleX, y: 1)
        ctx.textPosition = CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.15)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
