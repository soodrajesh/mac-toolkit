import SwiftUI
import UniformTypeIdentifiers

struct PDFSignView: View {
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var basePageCG: CGImage?
    @State private var displayImage: NSImage?
    @State private var placeRect: [CGRect] = []
    @State private var saved: URL?

    @State private var mode: Mode = .draw
    @State private var strokes: [[CGPoint]] = []
    @State private var typed = "Rajesh Sood"
    @State private var scriptFont = "Snell Roundhand"
    @State private var inkColor: Color = .black

    static let signatureFonts = [
        "Snell Roundhand", "Savoye LET", "Zapfino", "Apple Chancery", "Brush Script MT",
        "SignPainter", "Noteworthy", "Bradley Hand", "Marker Felt", "Chalkboard SE",
        "Herculanum", "Trattatello", "Papyrus",
    ]

    enum Mode: String, CaseIterable, Identifiable { case draw = "Draw", type = "Type"; var id: String { rawValue } }
    private let padSize = CGSize(width: 400, height: 150)
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // LEFT — controls
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sign PDF").font(.title2).bold()
                        Text("Draw or type a signature, then drag a box on the page to place it.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    DropWell(model: model)
                    if !model.files.isEmpty { FileList(model: model) }

                    if displayImage != nil {
                        signaturePanel
                            .onChange(of: strokes) { _ in updatePreview() }
                            .onChange(of: typed) { _ in updatePreview() }
                            .onChange(of: scriptFont) { _ in updatePreview() }
                            .onChange(of: inkColor) { _ in updatePreview() }
                            .onChange(of: mode) { _ in updatePreview() }

                        HStack(spacing: 10) {
                            Button("Apply Signature") { apply() }
                                .buttonStyle(.borderedProminent)
                                .disabled(placeRect.isEmpty || !hasSignature)
                            if let saved {
                                Button { revealInFinder([saved]) } label: {
                                    Label("Signed — Reveal in Finder", systemImage: "checkmark.circle.fill")
                                }.foregroundStyle(.green)
                            }
                        }
                        if let error = model.error { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    }
                }
                .padding(20)
            }
            .frame(width: 470)

            Divider()

            // RIGHT — zoomable page preview
            if let displayImage {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        if pageCount > 1 {
                            Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(pageIndex == 0)
                            Text("Page \(pageIndex + 1) / \(pageCount)").font(.callout)
                            Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(pageIndex >= pageCount - 1)
                            Divider().frame(height: 16)
                        }
                        Button { setZoom(zoom - 0.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 44)
                        Button { setZoom(zoom + 0.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        Button("Fit") { setZoom(1) }.disabled(zoom == 1)
                        Spacer()
                        Text(placeRect.isEmpty ? "Drag a box to place the signature" : "Pinch/scroll to zoom for precision")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    zoomablePage(displayImage)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack { Spacer(); Text("Drop a PDF to begin").foregroundStyle(.secondary); Spacer() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: model.files) { _ in zoom = 1; lastZoom = 1; load() }
    }

    private func zoomablePage(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let pageAspect = image.size.height / max(1, image.size.width)
            let dW = min(geo.size.width, geo.size.height / pageAspect)
            let dH = dW * pageAspect
            ScrollView([.horizontal, .vertical]) {
                RegionSelector(image: image, rects: $placeRect, singleSelection: true)
                    .frame(width: dW * zoom, height: dH * zoom)
                    .onChange(of: placeRect) { _ in updatePreview() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { v in zoom = min(5, max(1, lastZoom * v)) }
                    .onEnded { _ in lastZoom = zoom }
            )
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
    }

    private func setZoom(_ z: CGFloat) { zoom = min(5, max(1, z)); lastZoom = zoom }

    private var signaturePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Signature", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 180)
                    ColorPicker("Ink", selection: $inkColor, supportsOpacity: false).fixedSize()
                }
                if mode == .draw {
                    SignaturePad(strokes: $strokes, color: inkColor)
                        .frame(width: padSize.width, height: padSize.height)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.4)))
                    Button("Clear") { strokes = [] }.disabled(strokes.isEmpty)
                } else {
                    TextField("Signature text", text: $typed).textFieldStyle(.roundedBorder).frame(width: 300)
                    Picker("Font", selection: $scriptFont) {
                        ForEach(Self.signatureFonts, id: \.self) {
                            Text($0).font(.custom($0, size: 16)).tag($0)
                        }
                    }.frame(width: 240)
                }
            }.padding(6)
        } label: { Label("Signature", systemImage: "signature").font(.callout).bold() }
        .frame(maxWidth: 500, alignment: .leading)
    }

    private var hasSignature: Bool { mode == .draw ? !strokes.isEmpty : !typed.isEmpty }

    private func signatureImage() -> CGImage? {
        mode == .draw
            ? SignatureService.fromStrokes(strokes, size: padSize, color: NSColor(inkColor))
            : SignatureService.fromText(typed, fontName: scriptFont, color: NSColor(inkColor))
    }

    private func load() {
        placeRect = []; saved = nil; model.error = nil; pageIndex = 0
        guard let url = model.files.first else { basePageCG = nil; displayImage = nil; return }
        pageCount = max(1, PDFService.pageCount(url))
        basePageCG = PDFService.renderPageCGImage(url, page: 0)
        updatePreview()
    }
    private func step(_ d: Int) {
        guard let url = model.files.first else { return }
        pageIndex = min(max(0, pageIndex + d), pageCount - 1)
        basePageCG = PDFService.renderPageCGImage(url, page: pageIndex)
        updatePreview()
    }

    /// Composites the current signature into the placement box for a live preview.
    private func updatePreview() {
        guard let base = basePageCG else { displayImage = nil; return }
        guard let rect = placeRect.first, let sig = signatureImage() else {
            displayImage = NSImage(cgImage: base, size: NSSize(width: base.width, height: base.height)); return
        }
        let w = base.width, h = base.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rw = rect.width * CGFloat(w), rh = rect.height * CGFloat(h)
        let rx = rect.minX * CGFloat(w)
        let ry = CGFloat(h) - rect.minY * CGFloat(h) - rh   // flip to bottom-left origin
        let box = CGRect(x: rx, y: ry, width: rw, height: rh)
        let scale = min(box.width / CGFloat(sig.width), box.height / CGFloat(sig.height))
        let sw = CGFloat(sig.width) * scale, sh = CGFloat(sig.height) * scale
        ctx.draw(sig, in: CGRect(x: box.midX - sw / 2, y: box.midY - sh / 2, width: sw, height: sh))
        if let out = ctx.makeImage() { displayImage = NSImage(cgImage: out, size: NSSize(width: w, height: h)) }
    }

    private func apply() {
        guard let url = model.files.first, let rect = placeRect.first, let sig = signatureImage() else { return }
        model.error = nil; saved = nil
        do {
            let out = OutputPath.make(for: url, dir: model.outputDir, suffix: "-signed", ext: "pdf")
            try PDFService.stampImage(url, image: sig, pageIndex: pageIndex, rect: rect, to: out)
            saved = out
        } catch { model.error = error.localizedDescription }
    }
}

/// A self-contained ink pad. The in-progress stroke lives locally so drawing only
/// redraws the pad (not the parent view); completed strokes are pushed to `strokes`.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    var color: Color
    @State private var current: [CGPoint] = []

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes + [current] {
                guard let first = stroke.first else { continue }
                var path = Path(); path.move(to: first)
                for p in stroke.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(color),
                           style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { current.append($0.location) }
                .onEnded { _ in if !current.isEmpty { strokes.append(current); current = [] } }
        )
        .onChange(of: strokes) { new in if new.isEmpty { current = [] } }   // Clear resets pad
    }
}
