import SwiftUI
import UniformTypeIdentifiers

struct ImageToolsView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var format: ImageService.Format = .jpeg
    @State private var quality = 0.7
    @State private var resize = false
    @State private var maxPixel = 2000.0

    // Live preview (first file)
    @State private var previewImage: NSImage?
    @State private var beforeBytes: Int64?
    @State private var afterBytes: Int?

    var body: some View {
        ToolScaffold(
            title: "Convert & Compress",
            subtitle: "Batch: drop many images to change format (HEIC → JPEG…), compress, cap size, and strip EXIF — all at once. For visual crop/rotate, use Image Editor.",
            model: model,
            runLabel: "Process",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Output format", selection: $format) {
                    ForEach(ImageService.Format.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: format) { _ in updatePreview() }

                if format.lossy {
                    HStack {
                        Text("Quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.1...1.0) { editing in if !editing { updatePreview() } }
                            .frame(width: 200)
                    }
                } else {
                    Text("\(format.label) is lossless — shrink further by resizing below.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Resize (cap largest side)", isOn: $resize)
                    .onChange(of: resize) { _ in updatePreview() }
                if resize {
                    HStack {
                        Text("Max: \(Int(maxPixel)) px")
                        Slider(value: $maxPixel, in: 200...6000, step: 100) { editing in if !editing { updatePreview() } }
                            .frame(width: 200)
                    }
                }
                Label("EXIF/GPS metadata is always stripped from output.",
                      systemImage: "location.slash").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in updatePreview() }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImagePreview(image: previewImage, caption: model.files.first?.lastPathComponent)
            if let b = beforeBytes, let a = afterBytes {
                let pct = b > 0 ? Int((1 - Double(a) / Double(b)) * 100) : 0
                HStack(spacing: 6) {
                    Text("Before \(b.humanBytes)").foregroundStyle(.secondary)
                    Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
                    Text("After ~\(Int64(a).humanBytes)").bold()
                    Text("(\(pct >= 0 ? "−" : "+")\(abs(pct))%)")
                        .foregroundStyle(pct >= 0 ? .green : .orange)
                }.font(.callout)
                Text("Estimate for the first file at current settings.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Drop an image to preview.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    /// Recomputes the first-file preview (compressed pixels + size estimate).
    private func updatePreview() {
        guard let url = model.files.first else { previewImage = nil; beforeBytes = nil; afterBytes = nil; return }
        beforeBytes = url.fileSize
        let cap = resize ? Int(maxPixel) : nil
        // Display: downsample to keep it light while honouring the user's cap.
        let displayCap = min(cap ?? 1600, 1600)
        if let img = try? ImageService.loadDownsampled(url, maxPixel: displayCap),
           let data = ImageService.encodeData(img, format: format, quality: quality),
           let src = CGImageSourceCreateWithData(data as CFData, nil),
           let decoded = CGImageSourceCreateImageAtIndex(src, 0, nil) {
            previewImage = NSImage(cgImage: decoded, size: NSSize(width: decoded.width, height: decoded.height))
        }
        // Accurate size: encode at the real output resolution.
        if let full = try? ImageService.loadDownsampled(url, maxPixel: cap) {
            afterBytes = ImageService.encodeData(full, format: format, quality: quality)?.count
        }
    }

    private func run() {
        let dir = model.outputDir
        let fmt = format, q = quality
        let cap = resize ? Int(maxPixel) : nil
        model.run { files in
            var r = JobResult()
            for url in files {
                do {
                    let (out, before, after) = try ImageService.process(
                        url, format: fmt, quality: q, maxPixel: cap, dir: dir, suffix: "-out")
                    r.outputs.append(out)
                    let pct = before > 0 ? Int((1 - Double(after) / Double(before)) * 100) : 0
                    r.messages.append("\(url.lastPathComponent): \(before.humanBytes) → \(after.humanBytes) (\(pct >= 0 ? "−" : "+")\(abs(pct))%)")
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return r
        }
    }
}
