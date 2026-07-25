import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import CoreGraphics

/// QR code generation (CoreImage) and reading (Vision).
enum QRService {

    /// Renders `text` as a QR CGImage of roughly `size`×`size` px.
    static func generate(_ text: String, size: Int, correction: String = "M") -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction
        guard let output = filter.outputImage else { return nil }
        let scale = CGFloat(size) / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    /// Detects QR/barcodes in an image file, returning decoded payloads.
    static func read(_ url: URL) throws -> [String] {
        let img = try ImageService.loadCGImage(url)
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }
}
