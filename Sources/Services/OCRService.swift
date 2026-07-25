import AppKit
import Vision
import PDFKit
import CoreGraphics

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
}
