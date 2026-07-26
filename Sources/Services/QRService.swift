import CoreImage
import CoreImage.CIFilterBuiltins
import Vision
import CoreGraphics

/// Barcode/QR generation (CoreImage) and reading (Vision, all symbologies).
enum QRService {

    enum BarcodeType: String, CaseIterable, Identifiable {
        case qr = "QR Code"
        case code128 = "Code 128"
        case pdf417 = "PDF417"
        case aztec = "Aztec"
        var id: String { rawValue }
    }

    /// Renders `text` as a barcode CGImage of roughly `size`×`size` px
    /// (linear symbologies like Code 128 keep a fixed height instead).
    static func generate(_ text: String, size: Int, type: BarcodeType = .qr, correction: String = "M") -> CGImage? {
        let data = Data(text.utf8)
        let output: CIImage?
        switch type {
        case .qr:
            let filter = CIFilter.qrCodeGenerator()
            filter.message = data
            filter.correctionLevel = correction
            output = filter.outputImage
        case .code128:
            let filter = CIFilter.code128BarcodeGenerator()
            filter.message = data
            output = filter.outputImage
        case .pdf417:
            let filter = CIFilter.pdf417BarcodeGenerator()
            filter.message = data
            output = filter.outputImage
        case .aztec:
            let filter = CIFilter.aztecCodeGenerator()
            filter.message = data
            output = filter.outputImage
        }
        guard let output else { return nil }
        let isLinear = type == .code128 || type == .pdf417
        let scaleX = CGFloat(size) / output.extent.width
        let scaleY = isLinear ? CGFloat(size) / 4 / output.extent.height : scaleX
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }

    struct Decoded { var payload: String; var symbology: String }

    /// Detects barcodes/QR of any supported symbology in an image file.
    static func read(_ url: URL) throws -> [Decoded] {
        let img = try ImageService.loadCGImage(url)
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let payload = obs.payloadStringValue else { return nil }
            return Decoded(payload: payload, symbology: obs.symbology.rawValue)
        }
    }
}
