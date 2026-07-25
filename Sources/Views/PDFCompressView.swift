import SwiftUI
import UniformTypeIdentifiers

struct PDFCompressView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var useGhostscript = Ghostscript.isAvailable
    @State private var gsPreset: Ghostscript.Preset = .ebook
    @State private var dpi = 150.0
    @State private var quality = 0.6

    var body: some View {
        ToolScaffold(
            title: "Compress PDF",
            subtitle: "Shrink PDF file size. Great for scanned documents.",
            model: model,
            runLabel: "Compress",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if Ghostscript.isAvailable {
                    Toggle("Use Ghostscript (higher quality, keeps text)", isOn: $useGhostscript)
                    Label("Ghostscript detected", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("Ghostscript not found — using native compression. Install with `brew install ghostscript` for better results.",
                          systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }

                if useGhostscript && Ghostscript.isAvailable {
                    Picker("Preset", selection: $gsPreset) {
                        ForEach(Ghostscript.Preset.allCases) { Text($0.label).tag($0) }
                    }
                } else {
                    HStack {
                        Text("Resolution: \(Int(dpi)) dpi")
                        Slider(value: $dpi, in: 72...300, step: 12).frame(width: 180)
                    }
                    HStack {
                        Text("JPEG quality: \(Int(quality * 100))%")
                        Slider(value: $quality, in: 0.2...0.9).frame(width: 180)
                    }
                    Text("Native mode rasterizes pages (selectable text becomes an image).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func run() {
        let useGS = useGhostscript && Ghostscript.isAvailable
        let preset = gsPreset
        let d = dpi, q = quality
        let dir = model.outputDir
        model.run { files in
            var result = JobResult()
            for url in files {
                let out = OutputPath.make(for: url, dir: dir, suffix: "-compressed", ext: "pdf")
                do {
                    if useGS {
                        try Ghostscript.compress(url, to: out, preset: preset)
                    } else {
                        try PDFService.compressNative(url, dpi: d, quality: q, to: out)
                    }
                    let before = url.fileSize, after = out.fileSize
                    let pct = before > 0 ? Int((1 - Double(after) / Double(before)) * 100) : 0
                    result.outputs.append(out)
                    result.messages.append("\(url.lastPathComponent): \(before.humanBytes) → \(after.humanBytes) (−\(pct)%)")
                } catch {
                    result.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return result
        }
    }
}
