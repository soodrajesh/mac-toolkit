import SwiftUI
import UniformTypeIdentifiers

struct WatermarkView: View {
    enum Mode: String, CaseIterable, Identifiable { case text = "Text", logo = "Logo image"; var id: String { rawValue } }

    @StateObject private var model = JobModel(types: [.image])
    @State private var mode: Mode = .text
    @State private var text = "© Your Name"
    @State private var fontFrac = 0.05
    @State private var color = Color.white
    @State private var logoURL: URL?
    @State private var logoCG: CGImage?
    @State private var widthFrac = 0.2
    @State private var opacity = 0.6
    @State private var placement: WatermarkService.Placement = .bottomRight

    @State private var previewImage: NSImage?

    var body: some View {
        ToolScaffold(
            title: "Watermark",
            subtitle: "Batch: stamp a text or logo watermark onto many images at once.",
            model: model,
            runLabel: "Apply",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !model.files.isEmpty {
                    let totalBytes = model.files.reduce(Int64(0)) { $0 + $1.fileSize }
                    MetadataLine(text: "\(model.files.count) image\(model.files.count == 1 ? "" : "s") · \(totalBytes.humanBytes) total")
                }
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 220)
                .onChange(of: mode) { _ in updatePreview() }

                if mode == .text {
                    TextField("Watermark text", text: $text)
                        .textFieldStyle(.roundedBorder).frame(width: 280)
                        .onChange(of: text) { _ in updatePreview() }
                    ColorPicker("Color", selection: $color)
                        .onChange(of: color) { _ in updatePreview() }
                    HStack {
                        Text("Size: \(Int(fontFrac * 100))% of width")
                        Slider(value: $fontFrac, in: 0.02...0.15) { editing in if !editing { updatePreview() } }
                            .frame(width: 200)
                    }
                } else {
                    HStack {
                        Button("Choose logo…") { chooseLogo() }
                        Text(logoURL?.lastPathComponent ?? "No logo selected").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Size: \(Int(widthFrac * 100))% of width")
                        Slider(value: $widthFrac, in: 0.05...0.6) { editing in if !editing { updatePreview() } }
                            .frame(width: 200)
                    }
                }

                Picker("Placement", selection: $placement) {
                    ForEach(WatermarkService.Placement.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 240)
                .onChange(of: placement) { _ in updatePreview() }

                HStack {
                    Text("Opacity: \(Int(opacity * 100))%")
                    Slider(value: $opacity, in: 0.05...1.0) { editing in if !editing { updatePreview() } }
                        .frame(width: 200)
                }
            }
        }
        .onChange(of: model.files) { _ in updatePreview() }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            ImagePreview(image: previewImage, caption: model.files.first?.lastPathComponent)
            if model.files.isEmpty { Text("Drop an image to preview.").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func chooseLogo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            logoURL = url
            logoCG = try? ImageService.loadCGImage(url)
            updatePreview()
        }
    }

    private func watermark(_ cg: CGImage) -> CGImage? {
        switch mode {
        case .text:
            return WatermarkService.applyText(cg, text: text, fontName: "Helvetica", fontFrac: fontFrac,
                                              color: NSColor(color), opacity: opacity, placement: placement)
        case .logo:
            guard let logoCG else { return cg }
            return WatermarkService.applyImage(cg, logo: logoCG, widthFrac: widthFrac, opacity: opacity, placement: placement)
        }
    }

    private func updatePreview() {
        guard let url = model.files.first, let src = try? ImageService.loadDownsampled(url, maxPixel: 1200),
              let out = watermark(src) else { previewImage = nil; return }
        previewImage = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    private func run() {
        let dir = model.outputDir
        let m = mode, t = text, ff = fontFrac, c = NSColor(color)
        let logo = logoCG, wf = widthFrac, op = opacity, pl = placement
        model.runWithProgress { files, report in
            guard m == .text || logo != nil else { throw JobError.badInput("Choose a logo image first") }
            var r = JobResult()
            let total = files.count
            for (i, url) in files.enumerated() {
                if Task.isCancelled { break }
                do {
                    let src = try ImageService.loadCGImage(url)
                    let out: CGImage?
                    switch m {
                    case .text:
                        out = WatermarkService.applyText(src, text: t, fontName: "Helvetica", fontFrac: ff,
                                                         color: c, opacity: op, placement: pl)
                    case .logo:
                        out = WatermarkService.applyImage(src, logo: logo!, widthFrac: wf, opacity: op, placement: pl)
                    }
                    guard let out else { throw JobError.failed("Could not render watermark") }
                    let dest = OutputPath.make(for: url, dir: dir, suffix: "-watermarked", ext: "png")
                    try ImageService.write(out, to: dest, format: .png, quality: 1)
                    r.outputs.append(dest)
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                report(Double(i + 1) / Double(total))
            }
            return r
        }
    }
}
