import SwiftUI
import UniformTypeIdentifiers

struct BlurView: View {
    @StateObject private var model = JobModel(types: [.image], multiple: false)
    @State private var source: CGImage?
    @State private var preview: CGImage?
    @State private var rects: [CGRect] = []
    @State private var pixelate = true
    @State private var intensity = 20.0
    @State private var saved: URL?
    @State private var detectError: String?
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Blur / Pixelate",
            subtitle: "Drag over regions to hide faces, addresses, or numbers before sharing.",
            model: model,
            runLabel: "Apply & Save",
            onRun: save,
            secondaryLabel: "Auto-detect faces",
            onSecondary: detectFaces,
            clearLabel: "Clear Regions",
            onClear: { rects = [] },
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: $pixelate) {
                    Text("Pixelate").tag(true); Text("Blur").tag(false)
                }.pickerStyle(.segmented).frame(width: 220)
                .onChange(of: pixelate) { _ in updatePreview() }

                HStack {
                    Text(pixelate ? "Block size: \(Int(intensity))" : "Radius: \(Int(intensity))")
                    Slider(value: $intensity, in: 5...60) { editing in
                        if !editing { updatePreview() }
                    }.frame(width: 200)
                }

                if let detectError {
                    Text(detectError).font(.caption).foregroundStyle(.orange)
                }

                if let saved {
                    Button { revealInFinder([saved]) } label: {
                        Label("Saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                    }.foregroundStyle(.green)
                }
            }
        }
        .onChange(of: model.files) { _ in
            rects = []; saved = nil; preview = nil; detectError = nil
            source = model.files.first.flatMap { try? ImageService.loadCGImage($0) }
            info = model.files.first.map { FileInfoService.imageFields($0) } ?? []
        }
    }

    private var previewPane: some View {
        VStack(spacing: 12) {
            if let source {
                let shown = preview ?? source
                let ns = NSImage(cgImage: shown, size: NSSize(width: shown.width, height: shown.height))
                RegionSelector(image: ns, rects: $rects)
                    .frame(minHeight: 200, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
                    .onChange(of: rects) { _ in updatePreview() }

                HStack(spacing: 8) {
                    Text("Live preview — the boxes show what will be obscured.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !rects.isEmpty {
                        Text("\(rects.count) region\(rects.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                ImagePreview(image: nil, caption: "Drop an image")
            }

            if !info.isEmpty {
                MetadataPanel(fields: info)
            }
            Spacer(minLength: 0)
        }
    }

    private func detectFaces() {
        guard let src = source else { return }
        let found = FaceDetectionService.detectFaces(src)
        detectError = found.isEmpty ? "No faces detected" : nil
        if !found.isEmpty { rects.append(contentsOf: found); updatePreview() }
    }

    private func updatePreview() {
        guard let src = source else { preview = nil; return }
        preview = rects.isEmpty ? nil
            : ImageEditService.obscure(src, rects: rects, pixelate: pixelate, intensity: intensity)
    }

    private func save() {
        guard let src = source, let file = model.files.first else { return }
        guard !rects.isEmpty else { model.error = "Draw at least one region first"; return }
        guard let out = ImageEditService.obscure(src, rects: rects, pixelate: pixelate, intensity: intensity) else {
            model.error = "Could not process"; return
        }
        let url = OutputPath.make(for: file, dir: model.outputDir, suffix: pixelate ? "-pixelated" : "-blurred", ext: "png")
        do { try ImageService.write(out, to: url, format: .png, quality: 1); saved = url }
        catch { model.error = error.localizedDescription }
    }
}
