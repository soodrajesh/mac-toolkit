import SwiftUI
import UniformTypeIdentifiers

struct IconGeneratorView: View {
    @StateObject private var model = JobModel(types: [.image], multiple: false)
    @State private var pngs = true
    @State private var ico = true
    @State private var icns = true
    @State private var square: NSImage?
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Icon Generator",
            subtitle: "Turn an image into a favicon + full app-icon set (center-cropped to square).",
            model: model,
            runLabel: "Generate",
            onRun: run,
            preview: {
                VStack(spacing: 12) {
                    ImagePreview(image: square, caption: "Square crop used for icons")

                    if !info.isEmpty {
                        MetadataPanel(fields: info)
                    }
                    Spacer(minLength: 0)
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("PNG set (16–1024 px)", isOn: $pngs)
                Toggle("favicon.ico (multi-resolution)", isOn: $ico)
                Toggle("AppIcon.icns (macOS)", isOn: $icns)
                Text("Outputs land in a \"<name>-icons\" folder next to the source.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in
            square = model.files.first.flatMap { try? ImageService.loadCGImage($0) }
                .map { IconService.square($0) }
                .map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
            info = model.files.first.map { FileInfoService.imageFields($0) } ?? []
        }
    }

    private func run() {
        let dir = model.outputDir
        let p = pngs, i = ico, n = icns
        if !(p || i || n) { model.error = "Select at least one output"; return }
        model.run { files in
            guard let src = files.first else { throw JobError.emptyInput }
            let outs = try IconService.generate(src, dir: dir, makeICO: i, makeICNS: n, makePNGs: p)
            var r = JobResult()
            r.outputs = outs
            r.messages.append("Generated \(outs.count) files")
            return r
        }
    }
}
