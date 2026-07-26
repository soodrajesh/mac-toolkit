import SwiftUI
import UniformTypeIdentifiers

struct CollageView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var layout: CollageService.Layout = .grid
    @State private var columns = 2
    @State private var cell = 400
    @State private var spacing = 12
    @State private var white = true
    @State private var previewImage: NSImage?

    // Freeform mode
    @State private var items: [Element] = []
    @State private var selected: UUID?
    @State private var aspect: CanvasAspect = .fourThree
    @State private var moveBaseline: CGPoint?
    @State private var availWidth: CGFloat = 700
    @State private var snapX = false      // element x snapped to canvas center
    @State private var snapY = false
    private let space = "collageCanvas"

    static let fonts = ["Helvetica Neue", "Helvetica", "Arial", "Avenir Next", "Georgia",
                        "Times New Roman", "Courier New", "Menlo", "Futura", "Impact",
                        "Marker Felt", "Snell Roundhand", "Chalkduster"]

    struct Element: Identifiable {
        let id = UUID()
        var isText: Bool
        var center: CGPoint
        var rotation: CGFloat = 0
        var opacity: Double = 1
        // image
        var url: URL?
        var ns: NSImage?
        var cg: CGImage?
        var aspect: CGFloat = 1
        var widthFrac: CGFloat = 0.3
        // text
        var text: String = "Your text"
        var fontName: String = "Helvetica Neue"
        var fontFrac: CGFloat = 0.08
        var color: Color = .black
        var bold: Bool = false
        var italic: Bool = false
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
            subtitle: "Grid/strip for a uniform layout, or Freeform to drag, resize, rotate images & text — a mini poster maker.",
            model: model,
            runLabel: isFreeform ? "Export PNG" : "Create Collage",
            onRun: run,
            previewVisible: !isFreeform,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Layout", selection: $layout) {
                    ForEach(CollageService.Layout.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                .onChange(of: layout) { _ in updatePreview() }

                if isFreeform {
                    freeformControls
                    if let idx = selectedIndex {
                        HStack {
                            Text("Opacity").foregroundStyle(.secondary)
                            Slider(value: $items[idx].opacity, in: 0.1...1).frame(width: 200)
                            Text("\(Int(items[idx].opacity * 100))%").font(.caption.monospacedDigit())
                        }
                        if items[idx].isText { textEditor(idx) }
                    }
                    widthReader
                    freeformCanvas
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
                    .pickerStyle(.segmented).frame(width: 160)
                Picker("BG", selection: $white) { Text("White").tag(true); Text("Black").tag(false) }
                    .pickerStyle(.segmented).frame(width: 110)
                Button { addText() } label: { Label("Add Text", systemImage: "textformat") }
            }
            HStack(spacing: 8) {
                Button { bring(forward: true) } label: { Label("Forward", systemImage: "square.3.layers.3d.top.filled") }.disabled(selected == nil)
                Button { bring(forward: false) } label: { Label("Back", systemImage: "square.3.layers.3d.bottom.filled") }.disabled(selected == nil)
                Button { deleteSelected() } label: { Label("Delete", systemImage: "trash") }.disabled(selected == nil)
            }
            Text("Drag to move, corner handle to resize, top handle to rotate. Tap empty space to deselect.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Editor shown when a text element is selected.
    private func textEditor(_ idx: Int) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Text", text: $items[idx].text, axis: .vertical)
                    .textFieldStyle(.roundedBorder).lineLimit(1...3)
                HStack {
                    Picker("Font", selection: $items[idx].fontName) {
                        ForEach(Self.fonts, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                    }.frame(width: 200)
                    ColorPicker("", selection: $items[idx].color, supportsOpacity: false).labelsHidden()
                    Toggle("B", isOn: $items[idx].bold).toggleStyle(.button).fontWeight(.bold)
                    Toggle("I", isOn: $items[idx].italic).toggleStyle(.button).italic()
                }
                HStack {
                    Text("Size").foregroundStyle(.secondary)
                    Slider(value: $items[idx].fontFrac, in: 0.02...0.4).frame(width: 200)
                }
            }.padding(6)
        } label: { Label("Text", systemImage: "textformat").font(.callout).bold() }
        .frame(maxWidth: 460, alignment: .leading)
    }

    // MARK: Preview / canvas

    private var previewPane: some View {
        VStack {
            ImagePreview(image: previewImage,
                         caption: model.files.isEmpty ? "Add images to preview" : "Live collage preview")
            Spacer()
        }
    }

    private var widthReader: some View {
        GeometryReader { g in
            Color.clear.onAppear { availWidth = g.size.width }
                .onChange(of: g.size.width) { availWidth = $0 }
        }.frame(height: 0)
    }

    private var freeformCanvas: some View {
        var dW = max(320, min(availWidth, 1000))
        var dH = dW / aspect.ratio
        let capH: CGFloat = 640
        if dH > capH { dH = capH; dW = dH * aspect.ratio }
        let cw = dW, ch = dH
        return HStack {
            Spacer(minLength: 0)
            ZStack {
                Rectangle().fill(white ? Color.white : Color.black)
                ForEach($items) { $it in itemLayer($it, dW: cw, dH: ch) }
                if snapX { Rectangle().fill(Color.pink).frame(width: 1).frame(maxHeight: .infinity) }
                if snapY { Rectangle().fill(Color.pink).frame(height: 1).frame(maxWidth: .infinity) }
            }
            .frame(width: cw, height: ch)
            .coordinateSpace(name: space)
            .overlay(Rectangle().strokeBorder(.gray.opacity(0.35)))
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
            Spacer(minLength: 0)
        }
        .frame(height: ch + 8)
    }

    @ViewBuilder
    private func itemLayer(_ it: Binding<Element>, dW: CGFloat, dH: CGFloat) -> some View {
        let el = it.wrappedValue
        let sz = displaySize(el, dW: dW)
        let c = CGPoint(x: el.center.x * dW, y: el.center.y * dH)
        let isSel = selected == el.id

        Group {
            if el.isText {
                Text(el.text.isEmpty ? " " : el.text)
                    .font(Font(FreeformService.makeFont(el.fontName, size: el.fontFrac * dW, bold: el.bold, italic: el.italic) as CTFont))
                    .foregroundColor(el.color)
                    .fixedSize()
            } else if let ns = el.ns {
                Image(nsImage: ns).resizable().frame(width: sz.width, height: sz.height)
            }
        }
        .opacity(el.opacity)
        .overlay(isSel ? Rectangle().strokeBorder(Color.accentColor, lineWidth: 2) : nil)
        .rotationEffect(.radians(Double(el.rotation)))
        .position(c)
        .gesture(moveGesture(it, dW: dW, dH: dH))
        .onTapGesture { selected = el.id }

        if isSel {
            handle("arrow.up.left.and.arrow.down.right")
                .position(rotated(offset: CGPoint(x: sz.width / 2, y: sz.height / 2), around: c, angle: el.rotation))
                .gesture(resizeGesture(it, dW: dW, dH: dH))
            handle("arrow.triangle.2.circlepath")
                .position(rotated(offset: CGPoint(x: 0, y: -sz.height / 2 - 20), around: c, angle: el.rotation))
                .gesture(rotateGesture(it, dW: dW, dH: dH))
        }
    }

    private func handle(_ system: String) -> some View {
        Image(systemName: system).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(Color.accentColor))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
    }

    /// On-screen size of an element in canvas points.
    private func displaySize(_ el: Element, dW: CGFloat) -> CGSize {
        if el.isText {
            let font = FreeformService.makeFont(el.fontName, size: el.fontFrac * dW, bold: el.bold, italic: el.italic)
            let s = NSAttributedString(string: el.text.isEmpty ? " " : el.text, attributes: [.font: font]).size()
            return CGSize(width: max(8, s.width), height: max(8, s.height))
        }
        let w = el.widthFrac * dW
        return CGSize(width: w, height: w * el.aspect)
    }

    // MARK: Gestures

    private func moveGesture(_ it: Binding<Element>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                if moveBaseline == nil { moveBaseline = it.wrappedValue.center; selected = it.wrappedValue.id }
                var c = moveBaseline!
                c.x = min(max(c.x + (v.location.x - v.startLocation.x) / dW, 0), 1)
                c.y = min(max(c.y + (v.location.y - v.startLocation.y) / dH, 0), 1)
                // Snap to canvas center / edges with a small threshold.
                let t: CGFloat = 0.012
                snapX = false; snapY = false
                for target in [0.0, 0.5, 1.0] {
                    if abs(c.x - target) < t { c.x = target; if target == 0.5 { snapX = true } }
                    if abs(c.y - target) < t { c.y = target; if target == 0.5 { snapY = true } }
                }
                it.wrappedValue.center = c
            }
            .onEnded { _ in moveBaseline = nil; snapX = false; snapY = false }
    }
    private func resizeGesture(_ it: Binding<Element>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                let el = it.wrappedValue
                let c = CGPoint(x: el.center.x * dW, y: el.center.y * dH)
                let L = hypot(v.location.x - c.x, v.location.y - c.y)
                if el.isText {
                    let ds = displaySize(el, dW: dW)
                    let halfDiag = hypot(ds.width, ds.height) / 2
                    if halfDiag > 0 { it.wrappedValue.fontFrac = max(0.01, min(1.5, L * el.fontFrac / halfDiag)) }
                } else {
                    let a = el.aspect
                    it.wrappedValue.widthFrac = max(0.03, min(2.5, (2 * L / sqrt(1 + a * a)) / dW))
                }
            }
    }
    private func rotateGesture(_ it: Binding<Element>, dW: CGFloat, dH: CGFloat) -> some Gesture {
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

    private var selectedIndex: Int? { selected.flatMap { s in items.firstIndex { $0.id == s } } }

    private func addText() {
        var el = Element(isText: true, center: CGPoint(x: 0.5, y: 0.35))
        el.color = white ? .black : .white
        items.append(el)
        selected = el.id
    }

    private func sync() {
        items.removeAll { el in !el.isText && (el.url.map { !model.files.contains($0) } ?? true) }
        for url in model.files where !items.contains(where: { $0.url == url }) {
            guard let cg = try? ImageService.loadCGImage(url) else { continue }
            let ns = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            let imgCount = items.filter { !$0.isText }.count
            let off = CGFloat(imgCount % 6) * 0.05
            var el = Element(isText: false, center: CGPoint(x: 0.35 + off, y: 0.35 + off))
            el.url = url; el.ns = ns; el.cg = cg
            el.aspect = CGFloat(cg.height) / CGFloat(cg.width); el.widthFrac = 0.3
            items.append(el)
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
        guard let s = selected, let el = items.first(where: { $0.id == s }) else { return }
        selected = nil
        if let u = el.url { model.remove(u) } else { items.removeAll { $0.id == s } }
    }

    // MARK: Static grid preview

    private func updatePreview() {
        guard !isFreeform, !model.files.isEmpty else { return }
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
        let fitems: [FreeformService.Item] = items.map { el in
            let content: FreeformService.Content = el.isText
                ? .text(el.text, fontName: el.fontName, fontFrac: el.fontFrac,
                        color: NSColor(el.color), bold: el.bold, italic: el.italic)
                : .image(el.cg!, aspect: el.aspect)
            return FreeformService.Item(content: content, center: el.center,
                                        widthFrac: el.widthFrac, rotation: el.rotation,
                                        opacity: CGFloat(el.opacity))
        }
        guard !fitems.isEmpty else { model.error = "Add images or text first"; return }
        guard let img = FreeformService.render(fitems, canvasW: canvasW, canvasH: canvasH,
                                               bg: white ? .white : .black) else { model.error = "Render failed"; return }
        let base = model.files.first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("poster.png")
        let out = OutputPath.make(for: base, dir: model.outputDir, suffix: "-poster", ext: "png")
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
