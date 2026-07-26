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

    // Freeform mode
    @State private var items: [Placed] = []
    @State private var selected: UUID?
    @State private var aspect: CanvasAspect = .fourThree
    @State private var moveBaseline: CGPoint?
    private let space = "collageCanvas"

    struct Placed: Identifiable {
        let id = UUID()
        let url: URL
        let ns: NSImage
        let cg: CGImage
        var center: CGPoint
        var widthFrac: CGFloat
        var rotation: CGFloat = 0
        let aspect: CGFloat
    }
    enum CanvasAspect: String, CaseIterable, Identifiable {
        case square = "1:1", fourThree = "4:3", sixteenNine = "16:9"
        var id: String { rawValue }
        var ratio: CGFloat { self == .square ? 1 : self == .fourThree ? 4.0 / 3 : 16.0 / 9 }
    }

    private var isFreeform: Bool { layout == .freeform }

    var body: some View {
        ToolScaffold(
            title: "Collage",
            subtitle: "Grid/strip for a uniform layout, or Freeform to drag, resize & rotate each image in the preview.",
            model: model,
            runLabel: isFreeform ? "Export PNG" : "Create Collage",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout", selection: $layout) {
                    ForEach(CollageService.Layout.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: layout) { _ in updatePreview() }

                if isFreeform {
                    freeformControls
                } else {
                    gridControls
                }
            }
        }
        .onChange(of: model.files) { _ in updatePreview(); sync() }
    }

    // MARK: Controls

    private var gridControls: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            Picker("Background", selection: $white) { Text("White").tag(true); Text("Black").tag(false) }
                .pickerStyle(.segmented).frame(width: 200).onChange(of: white) { _ in updatePreview() }
        }
    }

    private var freeformControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Picker("Canvas", selection: $aspect) { ForEach(CanvasAspect.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 170)
                Picker("BG", selection: $white) { Text("White").tag(true); Text("Black").tag(false) }
                    .pickerStyle(.segmented).frame(width: 120)
            }
            HStack(spacing: 8) {
                Button { bring(forward: true) } label: { Label("Forward", systemImage: "square.3.layers.3d.top.filled") }.disabled(selected == nil)
                Button { bring(forward: false) } label: { Label("Back", systemImage: "square.3.layers.3d.bottom.filled") }.disabled(selected == nil)
                Button { deleteSelected() } label: { Label("Delete", systemImage: "trash") }.disabled(selected == nil)
            }
            Text("Drag an image to move, corner handle to resize, top handle to rotate. Tap empty space to deselect.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Preview / canvas

    @ViewBuilder
    private var previewPane: some View {
        if isFreeform {
            VStack { freeformCanvas; Spacer() }
        } else {
            VStack {
                ImagePreview(image: previewImage,
                             caption: model.files.isEmpty ? "Add images to preview" : "Live collage preview")
                Spacer()
            }
        }
    }

    private var freeformCanvas: some View {
        let dW: CGFloat = 330
        let dH = dW / aspect.ratio
        return ZStack {
            Rectangle().fill(white ? Color.white : Color.black)
            ForEach($items) { $it in itemLayer($it, dW: dW, dH: dH) }
        }
        .frame(width: dW, height: dH)
        .coordinateSpace(name: space)
        .overlay(Rectangle().strokeBorder(.gray.opacity(0.35)))
        .contentShape(Rectangle())
        .onTapGesture { selected = nil }
    }

    @ViewBuilder
    private func itemLayer(_ it: Binding<Placed>, dW: CGFloat, dH: CGFloat) -> some View {
        let p = it.wrappedValue
        let w = p.widthFrac * dW
        let h = w * p.aspect
        let c = CGPoint(x: p.center.x * dW, y: p.center.y * dH)
        let isSel = selected == p.id

        Image(nsImage: p.ns).resizable().frame(width: w, height: h)
            .rotationEffect(.radians(Double(p.rotation)))
            .overlay(isSel ? Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                        .rotationEffect(.radians(Double(p.rotation))) : nil)
            .position(c)
            .gesture(moveGesture(it, dW: dW, dH: dH))
            .onTapGesture { selected = p.id }

        if isSel {
            handle("arrow.up.left.and.arrow.down.right")
                .position(rotated(offset: CGPoint(x: w / 2, y: h / 2), around: c, angle: p.rotation))
                .gesture(resizeGesture(it, dW: dW))
            handle("arrow.triangle.2.circlepath")
                .position(rotated(offset: CGPoint(x: 0, y: -h / 2 - 20), around: c, angle: p.rotation))
                .gesture(rotateGesture(it, dW: dW, dH: dH))
        }
    }

    private func handle(_ system: String) -> some View {
        Image(systemName: system).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
    }

    // MARK: Gestures

    private func moveGesture(_ it: Binding<Placed>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                if moveBaseline == nil { moveBaseline = it.wrappedValue.center; selected = it.wrappedValue.id }
                var c = moveBaseline!
                c.x = min(max(c.x + (v.location.x - v.startLocation.x) / dW, 0), 1)
                c.y = min(max(c.y + (v.location.y - v.startLocation.y) / dH, 0), 1)
                it.wrappedValue.center = c
            }
            .onEnded { _ in moveBaseline = nil }
    }
    private func resizeGesture(_ it: Binding<Placed>, dW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                let c = CGPoint(x: it.wrappedValue.center.x * dW, y: it.wrappedValue.center.y * (dW / aspect.ratio))
                let L = hypot(v.location.x - c.x, v.location.y - c.y)
                let a = it.wrappedValue.aspect
                it.wrappedValue.widthFrac = max(0.03, min(2.5, (2 * L / sqrt(1 + a * a)) / dW))
            }
    }
    private func rotateGesture(_ it: Binding<Placed>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                let c = CGPoint(x: it.wrappedValue.center.x * dW, y: it.wrappedValue.center.y * dH)
                it.wrappedValue.rotation = atan2(v.location.y - c.y, v.location.x - c.x) + .pi / 2
            }
    }
    private func rotated(offset: CGPoint, around c: CGPoint, angle: CGFloat) -> CGPoint {
        CGPoint(x: c.x + offset.x * cos(angle) - offset.y * sin(angle),
                y: c.y + offset.x * sin(angle) + offset.y * cos(angle))
    }

    // MARK: Model helpers

    private func sync() {
        items.removeAll { p in !model.files.contains(p.url) }
        for url in model.files where !items.contains(where: { $0.url == url }) {
            guard let cg = try? ImageService.loadCGImage(url) else { continue }
            let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            let off = CGFloat(items.count % 6) * 0.05
            items.append(Placed(url: url, ns: ns, cg: cg,
                                center: CGPoint(x: 0.35 + off, y: 0.35 + off),
                                widthFrac: 0.3, aspect: CGFloat(cg.height) / CGFloat(cg.width)))
        }
        if let s = selected, !items.contains(where: { $0.id == s }) { selected = nil }
    }
    private func bring(forward: Bool) {
        guard let s = selected, let i = items.firstIndex(where: { $0.id == s }) else { return }
        let j = forward ? i + 1 : i - 1
        guard j >= 0, j < items.count else { return }
        items.swapAt(i, j)
    }
    private func deleteSelected() {
        guard let s = selected, let p = items.first(where: { $0.id == s }) else { return }
        selected = nil; model.remove(p.url)
    }

    // MARK: Static grid preview

    private func updatePreview() {
        guard !isFreeform, !model.files.isEmpty else { if isFreeform { previewImage = nil }; return }
        let bg = white ? NSColor.white : NSColor.black
        if let img = try? CollageService.combine(model.files, layout: layout, columns: columns,
                                                 cell: min(cell, 200), spacing: max(1, spacing / 2), bg: bg) {
            previewImage = NSImage(cgImage: img, size: NSSize(width: img.width, height: img.height))
        }
    }

    // MARK: Run

    private func run() {
        if isFreeform { exportFreeform() } else { createGrid() }
    }

    private func exportFreeform() {
        let canvasW = 1600, canvasH = Int(1600 / aspect.ratio)
        let fitems = items.map {
            FreeformService.Item(cg: $0.cg, center: $0.center, widthFrac: $0.widthFrac,
                                 rotation: $0.rotation, aspect: $0.aspect)
        }
        guard let img = FreeformService.render(fitems, canvasW: canvasW, canvasH: canvasH,
                                               bg: white ? .white : .black) else { model.error = "Render failed"; return }
        let base = model.files.first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("canvas.png")
        let out = OutputPath.make(for: base, dir: model.outputDir, suffix: "-canvas", ext: "png")
        do { try ImageService.write(img, to: out, format: .png, quality: 1)
            var r = JobResult(); r.outputs.append(out); r.messages.append("Exported \(img.width)×\(img.height)")
            model.result = r
        } catch { model.error = error.localizedDescription }
    }

    private func createGrid() {
        let l = layout, cols = columns, c = cell, sp = spacing
        let bg = white ? NSColor.white : NSColor.black
        let dir = model.outputDir
        model.run { files in
            let img = try CollageService.combine(files, layout: l, columns: cols, cell: c, spacing: sp, bg: bg)
            let out = OutputPath.make(for: files[0], dir: dir, suffix: "-collage", ext: "png")
            try ImageService.write(img, to: out, format: .png, quality: 1)
            var r = JobResult(); r.outputs.append(out)
            r.messages.append("Combined \(files.count) images (\(img.width)×\(img.height))")
            return r
        }
    }
}
