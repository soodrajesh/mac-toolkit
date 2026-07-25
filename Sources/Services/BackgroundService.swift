import Vision
import CoreImage
import CoreGraphics
import Foundation

/// One-click subject cutout: removes the background, producing a transparent PNG.
/// Requires macOS 14 (VNGenerateForegroundInstanceMaskRequest).
enum BackgroundService {

    static var isAvailable: Bool {
        if #available(macOS 14.0, *) { return true } else { return false }
    }

    static func removeBackground(_ url: URL, to output: URL) throws {
        guard #available(macOS 14.0, *) else {
            throw JobError.failed("Background removal needs macOS 14 or later")
        }
        let img = try ImageService.loadCGImage(url)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: img, options: [:])
        try handler.perform([request])

        guard let result = request.results?.first else {
            throw JobError.failed("No subject detected in image")
        }
        let buffer = try result.generateMaskedImage(
            ofInstances: result.allInstances,
            from: handler,
            croppedToInstancesExtent: false)

        let ci = CIImage(cvPixelBuffer: buffer)
        guard let cg = CIContext().createCGImage(ci, from: ci.extent) else {
            throw JobError.failed("Could not render cutout")
        }
        try ImageService.write(cg, to: output, format: .png, quality: 1)
    }
}
