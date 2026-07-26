import AppKit
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

/// PDFKit-backed operations: merge, split, page ops, render, compress, secure.
enum PDFService {

    static func open(_ url: URL, password: String? = nil) throws -> PDFDocument {
        guard let doc = PDFDocument(url: url) else { throw JobError.cannotOpen(url) }
        if doc.isLocked, let pw = password { _ = doc.unlock(withPassword: pw) }
        if doc.isLocked { throw JobError.badInput("\(url.lastPathComponent) is password-protected") }
        return doc
    }

    // MARK: Merge

    static func merge(_ urls: [URL], to output: URL) throws {
        guard !urls.isEmpty else { throw JobError.emptyInput }
        let merged = PDFDocument()
        var index = 0
        for url in urls {
            let doc = try open(url)
            for p in 0..<doc.pageCount {
                if let page = doc.page(at: p) {
                    merged.insert(page, at: index)
                    index += 1
                }
            }
        }
        guard merged.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    // MARK: Split

    /// Splits into one file per page.
    static func splitEachPage(_ url: URL, dir: URL?) throws -> [URL] {
        let doc = try open(url)
        var outputs: [URL] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let single = PDFDocument()
            single.insert(page, at: 0)
            let out = OutputPath.make(for: url, dir: dir, suffix: "-p\(p + 1)", ext: "pdf")
            guard single.write(to: out) else { throw JobError.cannotWrite(out) }
            outputs.append(out)
        }
        return outputs
    }

    /// Splits by 1-based inclusive ranges, e.g. [(1,3),(4,10)].
    static func split(_ url: URL, ranges: [(Int, Int)], dir: URL?) throws -> [URL] {
        let doc = try open(url)
        var outputs: [URL] = []
        for (i, range) in ranges.enumerated() {
            let sub = PDFDocument()
            var idx = 0
            for pageNo in range.0...range.1 {
                let z = pageNo - 1
                guard z >= 0, z < doc.pageCount, let page = doc.page(at: z) else { continue }
                sub.insert(page, at: idx); idx += 1
            }
            guard idx > 0 else { continue }
            let out = OutputPath.make(for: url, dir: dir, suffix: "-part\(i + 1)", ext: "pdf")
            guard sub.write(to: out) else { throw JobError.cannotWrite(out) }
            outputs.append(out)
        }
        return outputs
    }

    /// Parses "1-3, 5, 8-10" into inclusive ranges.
    static func parseRanges(_ text: String) -> [(Int, Int)] {
        var result: [(Int, Int)] = []
        for chunk in text.split(whereSeparator: { $0 == "," || $0 == "\n" }) {
            let piece = chunk.trimmingCharacters(in: .whitespaces)
            if piece.isEmpty { continue }
            if piece.contains("-") {
                let parts = piece.split(separator: "-", maxSplits: 1).map {
                    Int($0.trimmingCharacters(in: .whitespaces))
                }
                if parts.count == 2, let a = parts[0], let b = parts[1] {
                    result.append((min(a, b), max(a, b)))
                }
            } else if let n = Int(piece) {
                result.append((n, n))
            }
        }
        return result
    }

    // MARK: Page operations (rotate / delete / extract)

    static func rotate(_ url: URL, degrees: Int, to output: URL) throws {
        let doc = try open(url)
        for p in 0..<doc.pageCount {
            if let page = doc.page(at: p) { page.rotation = normalizedRotation(page.rotation + degrees) }
        }
        guard doc.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    /// Extracts the given 1-based pages (in order) into a new PDF.
    static func extract(_ url: URL, pages: [Int], to output: URL) throws {
        let doc = try open(url)
        let out = PDFDocument()
        var idx = 0
        for pageNo in pages {
            let z = pageNo - 1
            guard z >= 0, z < doc.pageCount, let page = doc.page(at: z) else { continue }
            out.insert(page, at: idx); idx += 1
        }
        guard idx > 0 else { throw JobError.badInput("No valid pages selected") }
        guard out.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    /// Deletes the given 1-based pages, keeping the rest.
    static func delete(_ url: URL, pages: Set<Int>, to output: URL) throws {
        let doc = try open(url)
        let kept = (1...max(doc.pageCount, 1)).filter { !pages.contains($0) }
        try extract(url, pages: kept, to: output)
        _ = doc
    }

    private static func normalizedRotation(_ d: Int) -> Int {
        var r = d % 360
        if r < 0 { r += 360 }
        return r
    }

    // MARK: PDF <-> images

    /// Renders each page to a PNG/JPEG at `dpi`. Returns output URLs.
    static func toImages(_ url: URL, dpi: Double, format: ImageService.Format,
                         quality: Double, dir: URL?) throws -> [URL] {
        let doc = try open(url)
        var outputs: [URL] = []
        let scale = dpi / 72.0
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let w = Int((bounds.width * scale).rounded())
            let h = Int((bounds.height * scale).rounded())
            guard w > 0, h > 0,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
                continue
            }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)
            guard let cg = ctx.makeImage() else { continue }
            let out = OutputPath.make(for: url, dir: dir, suffix: "-p\(p + 1)", ext: format.ext)
            try ImageService.write(cg, to: out, format: format, quality: quality)
            outputs.append(out)
        }
        return outputs
    }

    /// Builds a PDF (one page per image) from image files.
    static func fromImages(_ urls: [URL], to output: URL) throws {
        guard !urls.isEmpty else { throw JobError.emptyInput }
        let doc = PDFDocument()
        var idx = 0
        for url in urls {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
                continue
            }
            doc.insert(page, at: idx); idx += 1
        }
        guard idx > 0 else { throw JobError.badInput("No readable images") }
        guard doc.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    // MARK: Compression

    /// Native compression: rasterize each page to JPEG at `dpi` and rebuild.
    /// Reliable shrink for scanned PDFs; rasterizes text (loses selectable text).
    static func compressNative(_ url: URL, dpi: Double, quality: Double, to output: URL) throws {
        let doc = try open(url)
        let out = PDFDocument()
        let scale = dpi / 72.0
        var idx = 0
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

            // Encode to JPEG in memory, then wrap in a PDF page at original size.
            let tmp = OutputPath.temp(ext: "jpg")
            try ImageService.write(cg, to: tmp, format: .jpeg, quality: quality)
            defer { try? FileManager.default.removeItem(at: tmp) }
            guard let nsImage = NSImage(contentsOf: tmp),
                  let newPage = PDFPage(image: nsImage) else { continue }
            newPage.setBounds(bounds, for: .mediaBox)
            out.insert(newPage, at: idx); idx += 1
        }
        guard idx > 0 else { throw JobError.failed("Nothing to compress") }
        guard out.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    // MARK: Redaction

    /// Renders a single page to a CGImage (for on-screen region selection / preview).
    static func renderPageCGImage(_ url: URL, page p: Int, dpi: Double = 150) -> CGImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: p) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    static func renderPageImage(_ url: URL, page p: Int, dpi: Double = 150) -> NSImage? {
        guard let cg = renderPageCGImage(url, page: p, dpi: dpi) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func pageCount(_ url: URL) -> Int { PDFDocument(url: url)?.pageCount ?? 0 }

    /// Permanently redacts: pages with rects are rasterized with black boxes painted
    /// (underlying text/content destroyed); other pages are copied as-is.
    /// Rects are normalized (0…1, top-left) per page index.
    static func redact(_ url: URL, rectsByPage: [Int: [CGRect]], to output: URL,
                       color: NSColor = .black, dpi: Double = 200) throws {
        let doc = try open(url)
        let out = PDFDocument()
        var idx = 0
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let rects = rectsByPage[p] ?? []
            if rects.isEmpty { out.insert(page, at: idx); idx += 1; continue }

            let bounds = page.bounds(for: .mediaBox)
            let scale = dpi / 72.0
            let w = Int((bounds.width * scale).rounded()), h = Int((bounds.height * scale).rounded())
            guard w > 0, h > 0,
                  let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { continue }
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.scaleBy(x: scale, y: scale)
            ctx.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            page.draw(with: .mediaBox, to: ctx)
            guard let cg = ctx.makeImage(),
                  let redacted = ImageEditService.redact(cg, rects: rects, color: color) else { continue }
            let nsImage = NSImage(cgImage: redacted, size: bounds.size)
            guard let newPage = PDFPage(image: nsImage) else { continue }
            newPage.setBounds(bounds, for: .mediaBox)
            out.insert(newPage, at: idx); idx += 1
        }
        guard idx > 0, out.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    // MARK: Security

    /// Adds a password. Both user (open) and owner (permissions) passwords set.
    static func encrypt(_ url: URL, password: String, to output: URL) throws {
        let doc = try open(url)
        let opts: [PDFDocumentWriteOption: Any] = [
            .userPasswordOption: password,
            .ownerPasswordOption: password,
        ]
        guard doc.write(to: output, withOptions: opts) else { throw JobError.cannotWrite(output) }
    }

    /// Removes a password (given the current one), writing an unprotected copy.
    static func decrypt(_ url: URL, password: String, to output: URL) throws {
        let doc = try open(url, password: password)
        guard doc.write(to: output) else { throw JobError.cannotWrite(output) }
    }

    /// Stamps diagonal text across every page.
    static func watermark(_ url: URL, text: String, opacity: Double, to output: URL) throws {
        let doc = try open(url)
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            let annot = WatermarkAnnotation(bounds: bounds, text: text, opacity: opacity)
            page.addAnnotation(annot)
        }
        guard doc.write(to: output) else { throw JobError.cannotWrite(output) }
    }
}

/// A PDF annotation that draws diagonal watermark text spanning the page.
final class WatermarkAnnotation: PDFAnnotation {
    private let text: String
    private let opacity: Double

    init(bounds: CGRect, text: String, opacity: Double) {
        self.text = text
        self.opacity = opacity
        super.init(bounds: bounds, forType: .stamp, withProperties: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        context.saveGState()
        let rect = bounds
        let fontSize = max(rect.width, rect.height) * 0.09
        let font = NSFont.boldSystemFont(ofSize: fontSize)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.red.withAlphaComponent(CGFloat(opacity)),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()

        context.translateBy(x: rect.midX, y: rect.midY)
        context.rotate(by: .pi / 4)

        let nsCtx = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        str.draw(at: CGPoint(x: -size.width / 2, y: -size.height / 2))
        NSGraphicsContext.restoreGraphicsState()

        context.restoreGState()
    }
}
