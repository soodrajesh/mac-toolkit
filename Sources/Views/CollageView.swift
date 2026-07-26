import SwiftUI
import UniformTypeIdentifiers

struct CollageView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var layout: CollageService.Layout = .grid
    @State private var columns = 2
    @State private var cell = 400
    @State private var spacing = 12
    @State private var white = true
    @State private var saved: URL?
    @State private var previewImage: NSImage?

    var body: some View {
        ToolScaffold(
            title: "Collage",
            subtitle: "Combine images into a grid or strip. Drag rows (or use arrows) to set order.",
            model: model,
            runLabel: "Create Collage",
            onRun: run,
            preview: {
                VStack {
                    ImagePreview(image: previewImage,
                                 caption: model.files.isEmpty ? "Add images to preview" : "Live collage preview")
                    Spacer()
                }
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout", selection: $layout) {
                    ForEach(CollageService.Layout.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 300)
                .onChange(of: layout) { _ in updatePreview() }

                if layout == .grid {
                    Stepper("Columns: \(columns)", value: $columns, in: 1...8).frame(width: 200)
                        .onChange(of: columns) { _ in updatePreview() }
                }
                HStack {
                    Text("Cell: \(cell) px"); Slider(value: .init(get: { Double(cell) }, set: { cell = Int($0) }), in: 150...800, step: 50) { e in if !e { updatePreview() } }.frame(width: 160)
                }
                HStack {
                    Text("Spacing: \(spacing) px"); Slider(value: .init(get: { Double(spacing) }, set: { spacing = Int($0) }), in: 0...40, step: 2) { e in if !e { updatePreview() } }.frame(width: 160)
                }
                Picker("Background", selection: $white) {
                    Text("White").tag(true); Text("Black").tag(false)
                }.pickerStyle(.segmented).frame(width: 200)
                .onChange(of: white) { _ in updatePreview() }
            }
        }
        .onChange(of: model.files) { _ in updatePreview() }
    }

    /// Recomputes a lightweight collage preview (small cells) from current settings.
    private func updatePreview() {
        guard !model.files.isEmpty else { previewImage = nil; return }
        let bg = white ? NSColor.white : NSColor.black
        let previewCell = min(cell, 200)
        if let img = try? CollageService.combine(model.files, layout: layout, columns: columns,
                                                 cell: previewCell, spacing: max(1, spacing / 2), bg: bg) {
            previewImage = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        }
    }

    private func run() {
        let l = layout, cols = columns, c = cell, sp = spacing
        let bg = white ? NSColor.white : NSColor.black
        let dir = model.outputDir
        model.run { files in
            let img = try CollageService.combine(files, layout: l, columns: cols, cell: c, spacing: sp, bg: bg)
            let base = files.first ?? files[0]
            let out = OutputPath.make(for: base, dir: dir, suffix: "-collage", ext: "png")
            try ImageService.write(img, to: out, format: .png, quality: 1)
            var r = JobResult()
            r.outputs.append(out)
            r.messages.append("Combined \(files.count) images (\(img.width)×\(img.height))")
            return r
        }
    }
}
