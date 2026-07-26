import Vision
import CoreGraphics

/// Face detection via Vision. Returns rects normalized (0…1, top-left origin)
/// to match RegionSelector/ImageEditService's convention, with a small margin
/// so blur/pixelate fully covers hairline and chin.
enum FaceDetectionService {
    static func detectFaces(_ cg: CGImage, margin: Double = 0.25) -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let results = request.results ?? []
        return results.map { obs in
            // Vision boxes are normalized bottom-left origin; flip to top-left.
            let b = obs.boundingBox
            let mx = b.width * margin, my = b.height * margin
            let expanded = CGRect(x: b.minX - mx / 2, y: b.minY - my / 2,
                                  width: b.width + mx, height: b.height + my)
            let topLeft = CGRect(x: expanded.minX, y: 1 - expanded.minY - expanded.height,
                                 width: expanded.width, height: expanded.height)
            return topLeft.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }
}
