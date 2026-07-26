import SwiftUI
import UniformTypeIdentifiers

struct PDFSignView: View {
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var pageImage: NSImage?
    @State private var placeRect: [CGRect] = []
    @State private var saved: URL?

    @State private var mode: Mode = .draw
    @State private var strokes: [[CGPoint]] = []
    @State private var current: [CGPoint] = []
    @State private var typed = "Rajesh Sood"
    @State private var scriptFont = "Snell Roundhand"
    @State private var inkColor: Color = .blue

    enum Mode: String, CaseIterable, Identifiable { case draw = "Draw", type = "Type"; var id: String { rawValue } }
    private let padSize = CGSize(width: 440, height: 150)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign PDF").font(.title2).bold()
                    Text("Draw or type a signature, then drag a box on the page to place it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                if let pageImage {
                    if pageCount > 1 {
                        HStack {
                            Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(pageIndex == 0)
                            Text("Page \(pageIndex + 1) of \(pageCount)")
                            Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(pageIndex >= pageCount - 1)
                            Spacer()
                        }
                    }
                    RegionSelector(image: pageImage, rects: $placeRect, singleSelection: true)
                        .frame(height: 360)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
                    Text(placeRect.isEmpty ? "Drag a box where the signature should go." : "Signature area set — Apply below.")
                        .font(.caption).foregroundStyle(.secondary)

                    signaturePanel

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
        .onChange(of: model.files) { _ in load() }
    }

    private var signaturePanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Picker("Signature", selection: $mode) { ForEach(Mode.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).frame(width: 180)
                    ColorPicker("Ink", selection: $inkColor, supportsOpacity: false).fixedSize()
                }
                if mode == .draw {
                    SignaturePad(strokes: $strokes, current: $current, color: inkColor)
                        .frame(width: padSize.width, height: padSize.height)
                        .background(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.4)))
                    Button("Clear") { strokes = []; current = [] }.disabled(strokes.isEmpty && current.isEmpty)
                } else {
                    TextField("Signature text", text: $typed).textFieldStyle(.roundedBorder).frame(width: 300)
                    Picker("Font", selection: $scriptFont) {
                        ForEach(["Snell Roundhand", "Zapfino", "Marker Felt", "Bradley Hand", "Chalkboard SE"], id: \.self) {
                            Text($0).font(.custom($0, size: 15)).tag($0)
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
        guard let url = model.files.first else { pageImage = nil; return }
        pageCount = max(1, PDFService.pageCount(url))
        pageImage = PDFService.renderPageImage(url, page: 0)
    }
    private func step(_ d: Int) {
        guard let url = model.files.first else { return }
        pageIndex = min(max(0, pageIndex + d), pageCount - 1)
        pageImage = PDFService.renderPageImage(url, page: pageIndex)
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

/// A simple ink pad that records strokes as point arrays.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @Binding var current: [CGPoint]
    var color: Color

    var body: some View {
        Canvas { ctx, _ in
            for stroke in strokes + [current] {
                guard let first = stroke.first else { continue }
                var path = Path(); path.move(to: first)
                for p in stroke.dropFirst() { path.addLine(to: p) }
                ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { current.append($0.location) }
                .onEnded { _ in if !current.isEmpty { strokes.append(current); current = [] } }
        )
    }
}
