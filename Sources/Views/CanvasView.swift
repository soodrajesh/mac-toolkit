import SwiftUI
import UniformTypeIdentifiers

/// Free-form layout: drop images, then drag to move, drag the corner to resize,
/// and the top handle to rotate. Export composites everything at full resolution.
struct CanvasView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var items: [Placed] = []
    @State private var selected: UUID?
    @State private var white = true
    @State private var aspect: CanvasAspect = .fourThree
    @State private var saved: URL?
    @State private var moveBaseline: CGPoint?

    private let space = "canvas"

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Canvas").font(.title2).bold()
                    Text("Free-form arrange: drag to move, corner to resize, top handle to rotate.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                controls
                canvas

                HStack(spacing: 10) {
                    Button("Export PNG") { export() }
                        .buttonStyle(.borderedProminent).disabled(items.isEmpty)
                    if let saved {
                        Button { revealInFinder([saved]) } label: {
                            Label("Saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                        }.foregroundStyle(.green)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in sync() }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Canvas", selection: $aspect) {
                ForEach(CanvasAspect.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).frame(width: 180)
            Picker("BG", selection: $white) { Text("White").tag(true); Text("Black").tag(false) }
                .pickerStyle(.segmented).frame(width: 130)
            Divider().frame(height: 18)
            Button { bring(forward: true) } label: { Image(systemName: "square.3.layers.3d.top.filled") }
                .disabled(selected == nil).help("Bring forward")
            Button { bring(forward: false) } label: { Image(systemName: "square.3.layers.3d.bottom.filled") }
                .disabled(selected == nil).help("Send back")
            Button { deleteSelected() } label: { Image(systemName: "trash") }
                .disabled(selected == nil).help("Delete selected")
            Spacer()
        }
    }

    private var canvas: some View {
        let displayH: CGFloat = 440
        let displayW = displayH * aspect.ratio
        return HStack {
            Spacer(minLength: 0)
            ZStack {
                Rectangle().fill(white ? Color.white : Color.black)
                ForEach($items) { $it in
                    itemLayer($it, dW: displayW, dH: displayH)
                }
            }
            .frame(width: displayW, height: displayH)
            .coordinateSpace(name: space)
            .overlay(Rectangle().strokeBorder(.gray.opacity(0.35)))
            .contentShape(Rectangle())
            .onTapGesture { selected = nil }
            Spacer(minLength: 0)
        }
        .frame(height: displayH + 8)
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
            // Resize handle at the rotated bottom-right corner.
            handle(system: "arrow.up.left.and.arrow.down.right")
                .position(rotated(offset: CGPoint(x: w / 2, y: h / 2), around: c, angle: p.rotation))
                .gesture(resizeGesture(it, dW: dW, dH: dH))
            // Rotate handle above the top edge.
            handle(system: "arrow.triangle.2.circlepath")
                .position(rotated(offset: CGPoint(x: 0, y: -h / 2 - 22), around: c, angle: p.rotation))
                .gesture(rotateGesture(it, dW: dW, dH: dH))
        }
    }

    private func handle(system: String) -> some View {
        Image(systemName: system)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(Color.accentColor))
            .overlay(Circle().strokeBorder(.white, lineWidth: 1))
    }

    // MARK: Gestures

    private func moveGesture(_ it: Binding<Placed>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                if moveBaseline == nil { moveBaseline = it.wrappedValue.center; selected = it.wrappedValue.id }
                let dx = (v.location.x - v.startLocation.x) / dW
                let dy = (v.location.y - v.startLocation.y) / dH
                var c = moveBaseline!
                c.x = min(max(c.x + dx, 0), 1); c.y = min(max(c.y + dy, 0), 1)
                it.wrappedValue.center = c
            }
            .onEnded { _ in moveBaseline = nil }
    }

    private func resizeGesture(_ it: Binding<Placed>, dW: CGFloat, dH: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { v in
                let c = CGPoint(x: it.wrappedValue.center.x * dW, y: it.wrappedValue.center.y * dH)
                let L = hypot(v.location.x - c.x, v.location.y - c.y)
                let asp = it.wrappedValue.aspect
                let newW = 2 * L / sqrt(1 + asp * asp)
                it.wrappedValue.widthFrac = max(0.03, min(2.5, newW / dW))
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
        let cosA = cos(angle), sinA = sin(angle)
        return CGPoint(x: c.x + offset.x * cosA - offset.y * sinA,
                       y: c.y + offset.x * sinA + offset.y * cosA)
    }

    // MARK: Model

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
        if let sel = selected, !items.contains(where: { $0.id == sel }) { selected = nil }
    }

    private func bring(forward: Bool) {
        guard let sel = selected, let i = items.firstIndex(where: { $0.id == sel }) else { return }
        let j = forward ? i + 1 : i - 1
        guard j >= 0, j < items.count else { return }
        items.swapAt(i, j)
    }

    private func deleteSelected() {
        guard let sel = selected, let p = items.first(where: { $0.id == sel }) else { return }
        selected = nil
        model.remove(p.url)   // triggers sync()
    }

    private func export() {
        let canvasW = 1600
        let canvasH = Int(1600 / aspect.ratio)
        let fitems = items.map {
            FreeformService.Item(cg: $0.cg, center: $0.center, widthFrac: $0.widthFrac,
                                 rotation: $0.rotation, aspect: $0.aspect)
        }
        guard let img = FreeformService.render(fitems, canvasW: canvasW, canvasH: canvasH,
                                               bg: white ? .white : .black) else {
            model.error = "Render failed"; return
        }
        let base = model.files.first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("canvas.png")
        let out = OutputPath.make(for: base, dir: model.outputDir, suffix: "-canvas", ext: "png")
        do { try ImageService.write(img, to: out, format: .png, quality: 1); saved = out; revealInFinder([out]) }
        catch { model.error = error.localizedDescription }
    }
}
