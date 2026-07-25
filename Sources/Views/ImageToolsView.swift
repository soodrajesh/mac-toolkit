import SwiftUI
import UniformTypeIdentifiers

struct ImageToolsView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var format: ImageService.Format = .jpeg
    @State private var quality = 0.7
    @State private var resize = false
    @State private var maxPixel = 2000.0

    var body: some View {
        ToolScaffold(
            title: "Image Tools",
            subtitle: "Compress, convert (incl. HEIC → JPEG), resize, and strip EXIF.",
            model: model,
            runLabel: "Process",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Output format", selection: $format) {
                    ForEach(ImageService.Format.allCases) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)

                if format.lossy {
                    HStack {
                        Text("Quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.1...1.0).frame(width: 200)
                    }
                } else {
                    Text("\(format.label) is lossless — shrink further by resizing below.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Resize (cap largest side)", isOn: $resize)
                if resize {
                    HStack {
                        Text("Max: \(Int(maxPixel)) px")
                        Slider(value: $maxPixel, in: 200...6000, step: 100).frame(width: 200)
                    }
                }
                Label("EXIF/GPS metadata is always stripped from output.",
                      systemImage: "location.slash").font(.caption).foregroundStyle(.secondary)
            }
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
