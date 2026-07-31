import SwiftUI

/// Controls for image rotate and scale operations.
struct ImageTransformView: View {
    @Binding var rotation: Double
    @Binding var scale: Double
    let onReset: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transform", systemImage: "crop.rotate").font(.caption).foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rotate").font(.caption)
                        Spacer()
                        Text("\(Int(rotation))°").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Slider(value: $rotation, in: 0...360, step: 1).frame(maxWidth: .infinity)
                        Button("0°") { rotation = 0 }.controlSize(.small).buttonStyle(.bordered)
                        Button("90°") { rotation = 90 }.controlSize(.small).buttonStyle(.bordered)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Scale").font(.caption)
                        Spacer()
                        Text("\(String(format: "%.0f", scale * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        Slider(value: $scale, in: 0.1...3, step: 0.1).frame(maxWidth: .infinity)
                        Button("100%") { scale = 1 }.controlSize(.small).buttonStyle(.bordered)
                    }
                }

                Divider()

                Button(action: onReset) {
                    Label("Reset All", systemImage: "arrow.counterclockwise")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.06)))
        }
    }
}

/// Applies transform (rotation + scale) to a CGImage.
struct ImageTransformer {
    static func apply(rotation: Double, scale: Double, to cgImage: CGImage) -> CGImage? {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        // Calculate new size after rotation
        let radians = CGFloat(rotation * .pi / 180)
        let cos = abs(cos(radians))
        let sin = abs(sin(radians))
        let newWidth = width * cos + height * sin
        let newHeight = width * sin + height * cos

        // Apply scale
        let scaledWidth = newWidth * CGFloat(scale)
        let scaledHeight = newHeight * CGFloat(scale)

        guard let ctx = CGContext(
            data: nil,
            width: Int(scaledWidth),
            height: Int(scaledHeight),
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else { return nil }

        // Center and transform
        ctx.translateBy(x: scaledWidth / 2, y: scaledHeight / 2)
        ctx.rotate(by: radians)
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.translateBy(x: -width / 2, y: -height / 2)

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        return ctx.makeImage()
    }
}
