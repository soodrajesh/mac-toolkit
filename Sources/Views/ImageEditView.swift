import SwiftUI
import UniformTypeIdentifiers

struct ImageEditView: View {
    @StateObject private var model = JobModel(types: [.image], multiple: false)
    @State private var working: CGImage?
    @State private var cropRects: [CGRect] = []
    @State private var preset: ResizePreset = .none
    @State private var format: ImageService.Format = .png
    @State private var quality = 0.85
    @State private var saved: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Image Editor", "Crop, rotate, flip, and resize. Drag on the image to set a crop.")

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                if let working {
                    let ns = NSImage(cgImage: working, size: NSSize(width: working.width, height: working.height))
                    HStack(spacing: 8) {
                        Button { rotate(-1) } label: { Image(systemName: "rotate.left") }
                        Button { rotate(1) } label: { Image(systemName: "rotate.right") }
                        Button { flip(h: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                        Button { flip(v: true) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                        Divider().frame(height: 18)
                        Button("Apply Crop") { applyCrop() }.disabled(cropRects.isEmpty)
                        Button("Reset") { reload() }
                        Spacer()
                        Text("\(working.width)×\(working.height)").font(.caption).foregroundStyle(.secondary)
                    }

                    RegionSelector(image: ns, rects: $cropRects, singleSelection: true)
                        .frame(height: 340)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))

                    Picker("Resize", selection: $preset) {
                        ForEach(ResizePreset.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 320)

                    HStack {
                        Picker("Format", selection: $format) {
                            ForEach(ImageService.Format.allCases) { Text($0.label).tag($0) }
                        }.frame(width: 200)
                        if format.lossy {
                            Text("Quality \(Int(quality * 100))%")
                            Slider(value: $quality, in: 0.1...1).frame(width: 140)
                        }
                    }

                    Button("Save") { save() }.buttonStyle(.borderedProminent)

                    if let saved {
                        Button { revealInFinder([saved]) } label: {
                            Label("Saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                        }.foregroundStyle(.green)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in reload() }
    }

    private func reload() {
        cropRects = []; saved = nil
        working = model.files.first.flatMap { try? ImageService.loadCGImage($0) }
    }
    private func rotate(_ q: Int) { if let w = working { working = ImageEditService.rotate(w, quarters: q); cropRects = [] } }
    private func flip(h: Bool = false, v: Bool = false) { if let w = working { working = ImageEditService.flip(w, horizontal: h, vertical: v) } }
    private func applyCrop() {
        guard let w = working, let r = cropRects.first else { return }
        working = ImageEditService.crop(w, normRect: r); cropRects = []
    }

    private func save() {
        guard var out = working, let src = model.files.first else { return }
        if let box = preset.box, let resized = ImageEditService.resizeFit(out, maxW: box.0, maxH: box.1) {
            out = resized
        }
        let url = OutputPath.make(for: src, dir: model.outputDir, suffix: "-edited", ext: format.ext)
        do { try ImageService.write(out, to: url, format: format, quality: quality); saved = url }
        catch { model.error = error.localizedDescription }
    }

    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.title2).bold()
            Text(s).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
