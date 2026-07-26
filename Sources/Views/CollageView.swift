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

    var body: some View {
        ToolScaffold(
            title: "Collage",
            subtitle: "Combine images into a grid or strip. Drag rows to set order.",
            model: model,
            runLabel: "Create Collage",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout", selection: $layout) {
                    ForEach(CollageService.Layout.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 300)

                if layout == .grid {
                    Stepper("Columns: \(columns)", value: $columns, in: 1...8).frame(width: 200)
                }
                HStack {
                    Text("Cell: \(cell) px"); Slider(value: .init(get: { Double(cell) }, set: { cell = Int($0) }), in: 150...800, step: 50).frame(width: 160)
                }
                HStack {
                    Text("Spacing: \(spacing) px"); Slider(value: .init(get: { Double(spacing) }, set: { spacing = Int($0) }), in: 0...40, step: 2).frame(width: 160)
                }
                Picker("Background", selection: $white) {
                    Text("White").tag(true); Text("Black").tag(false)
                }.pickerStyle(.segmented).frame(width: 200)
            }
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
