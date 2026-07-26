import SwiftUI
import UniformTypeIdentifiers

struct BlurView: View {
    @StateObject private var model = JobModel(types: [.image], multiple: false)
    @State private var source: CGImage?
    @State private var rects: [CGRect] = []
    @State private var pixelate = true
    @State private var intensity = 20.0
    @State private var saved: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Blur / Pixelate").font(.title2).bold()
                    Text("Drag over regions to hide faces, addresses, or numbers before sharing.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                if let source {
                    let ns = NSImage(cgImage: source, size: NSSize(width: source.width, height: source.height))
                    RegionSelector(image: ns, rects: $rects)
                        .frame(height: 360)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))

                    Picker("Mode", selection: $pixelate) {
                        Text("Pixelate").tag(true); Text("Blur").tag(false)
                    }.pickerStyle(.segmented).frame(width: 220)
                    HStack {
                        Text(pixelate ? "Block size: \(Int(intensity))" : "Radius: \(Int(intensity))")
                        Slider(value: $intensity, in: 5...60).frame(width: 200)
                    }

                    HStack(spacing: 10) {
                        Button("Apply & Save") { save() }
                            .buttonStyle(.borderedProminent).disabled(rects.isEmpty)
                        Button("Clear regions") { rects = [] }.disabled(rects.isEmpty)
                        if !rects.isEmpty { Text("\(rects.count) region\(rects.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary) }
                    }

                    if let saved {
                        Button { revealInFinder([saved]) } label: {
                            Label("Saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                        }.foregroundStyle(.green)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in
            rects = []; saved = nil
            source = model.files.first.flatMap { try? ImageService.loadCGImage($0) }
        }
    }

    private func save() {
        guard let src = source, let file = model.files.first else { return }
        guard let out = ImageEditService.obscure(src, rects: rects, pixelate: pixelate, intensity: intensity) else {
            model.error = "Could not process"; return
        }
        let url = OutputPath.make(for: file, dir: model.outputDir, suffix: pixelate ? "-pixelated" : "-blurred", ext: "png")
        do { try ImageService.write(out, to: url, format: .png, quality: 1); saved = url }
        catch { model.error = error.localizedDescription }
    }
}
