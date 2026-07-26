import SwiftUI
import UniformTypeIdentifiers

struct ImageEditView: View {
    @StateObject private var model = JobModel(types: [.image], multiple: false)
    @State private var working: CGImage?
    @State private var cropRects: [CGRect] = []
    @State private var format: ImageService.Format = .png
    @State private var quality = 0.85
    @State private var saved: URL?
    @State private var selectionPx: CGSize?
    @State private var estimatedBytes: Int?

    // Resize & Skew (Paint-style)
    @State private var byPixels = false
    @State private var keepAspect = true
    @State private var hVal = 100.0
    @State private var vVal = 100.0
    @State private var skewH = 0.0
    @State private var skewV = 0.0

    // Text overlay
    @State private var addText = false
    @State private var overlayText = "Sample"
    @State private var textFont = "Helvetica Neue"
    @State private var textFrac = 0.06
    @State private var textColor: Color = .white
    @State private var textBold = false
    @State private var textItalic = false
    @State private var textAnchor: ImageEditService.StampAnchor = .bottomRight

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Image Editor", "Edit ONE image: crop (drag on it), rotate, flip, resize & skew, then save.")

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                if let working {
                    let shown = finalCG(working)
                    let ns = NSImage(cgImage: shown, size: NSSize(width: shown.width, height: shown.height))
                    HStack(spacing: 8) {
                        Button { rotate(-1) } label: { Image(systemName: "rotate.left") }
                        Button { rotate(1) } label: { Image(systemName: "rotate.right") }
                        Button { flip(h: true) } label: { Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right") }
                        Button { flip(v: true) } label: { Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down") }
                        Divider().frame(height: 18)
                        Button("Apply Crop") { applyCrop() }.disabled(cropRects.isEmpty)
                        Button("Reset") { reload() }
                        Spacer()
                    }

                    RegionSelector(image: ns, rects: $cropRects, singleSelection: true,
                                   onSelection: { updateSelection($0) })
                        .frame(height: 320)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))

                    // Status bar: dimensions, selection, file sizes.
                    HStack(spacing: 14) {
                        label("rectangle", "\(working.width) × \(working.height) px")
                        if let sel = selectionPx {
                            let wp = Int((sel.width / CGFloat(working.width) * 100).rounded())
                            let hp = Int((sel.height / CGFloat(working.height) * 100).rounded())
                            label("crop", "Selection \(Int(sel.width)) × \(Int(sel.height)) px  (\(wp)% × \(hp)%)")
                                .foregroundStyle(.primary)
                        }
                        Spacer()
                        if let src = model.files.first { label("doc", "Source \(src.fileSize.humanBytes)") }
                        if let est = estimatedBytes { label("arrow.down.doc", "Output ~\(Int64(est).humanBytes)") }
                    }
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)

                    resizeSkewPanel
                    textPanel

                    HStack {
                        Picker("Format", selection: $format) {
                            ForEach(ImageService.Format.allCases) { Text($0.label).tag($0) }
                        }.frame(width: 200)
                        .onChange(of: format) { _ in updateEstimate() }
                        if format.lossy {
                            Text("Quality \(Int(quality * 100))%")
                            Slider(value: $quality, in: 0.1...1) { editing in if !editing { updateEstimate() } }.frame(width: 140)
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

    // MARK: Resize & Skew panel

    private var resizeSkewPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Resize by:").frame(width: 90, alignment: .leading)
                    Picker("", selection: $byPixels) {
                        Text("Percentage").tag(false); Text("Pixels").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 220)
                    .onChange(of: byPixels) { _ in resetResizeFields() }
                }
                field("Horizontal:", value: $hVal, unit: byPixels ? "px" : "%", disabled: false) {
                    if keepAspect { syncVertical() }
                }
                field("Vertical:", value: $vVal, unit: byPixels ? "px" : "%", disabled: keepAspect) { }
                Toggle("Maintain aspect ratio", isOn: $keepAspect)
                    .onChange(of: keepAspect) { _ in if keepAspect { syncVertical() } }
                Button("Apply Resize") { applyResize() }

                Divider()

                HStack(spacing: 8) {
                    Text("Skew:").frame(width: 90, alignment: .leading)
                    Text("H").foregroundStyle(.secondary)
                    TextField("0", value: $skewH, format: .number).frame(width: 56).textFieldStyle(.roundedBorder)
                    Text("°  V").foregroundStyle(.secondary)
                    TextField("0", value: $skewV, format: .number).frame(width: 56).textFieldStyle(.roundedBorder)
                    Text("°").foregroundStyle(.secondary)
                    Button("Apply Skew") { applySkew() }
                }
            }
            .padding(6)
        } label: { Text("Resize & Skew").font(.callout).bold() }
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var textPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Add text overlay", isOn: $addText).onChange(of: addText) { _ in updateEstimate() }
                if addText {
                    TextField("Text", text: $overlayText).textFieldStyle(.roundedBorder).frame(width: 300)
                    HStack {
                        Picker("Font", selection: $textFont) {
                            ForEach(CollageView.fonts, id: \.self) { Text($0).font(.custom($0, size: 13)).tag($0) }
                        }.frame(width: 180)
                        ColorPicker("", selection: $textColor, supportsOpacity: false).labelsHidden()
                        Toggle("B", isOn: $textBold).toggleStyle(.button).fontWeight(.bold)
                        Toggle("I", isOn: $textItalic).toggleStyle(.button).italic()
                    }
                    HStack { Text("Size").foregroundStyle(.secondary); Slider(value: $textFrac, in: 0.02...0.25).frame(width: 180) }
                    Picker("Position", selection: $textAnchor) {
                        ForEach(ImageEditService.StampAnchor.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 220)
                }
            }.padding(6)
        } label: { Label("Text", systemImage: "textformat").font(.callout).bold() }
        .frame(maxWidth: 460, alignment: .leading)
    }

    /// Applies the text overlay (if enabled) on top of the working image.
    private func finalCG(_ base: CGImage) -> CGImage {
        guard addText, !overlayText.isEmpty else { return base }
        return ImageEditService.stampText(base, text: overlayText, fontName: textFont, fontFrac: textFrac,
                                          color: NSColor(textColor), bold: textBold, italic: textItalic,
                                          anchor: textAnchor) ?? base
    }

    private func field(_ title: String, value: Binding<Double>, unit: String,
                       disabled: Bool, onCommit: @escaping () -> Void) -> some View {
        HStack {
            Text(title).frame(width: 90, alignment: .leading)
            TextField("", value: value, format: .number)
                .frame(width: 80).textFieldStyle(.roundedBorder).disabled(disabled)
                .onChange(of: value.wrappedValue) { _ in onCommit() }
            Text(unit).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func reload() {
        cropRects = []; saved = nil; selectionPx = nil; skewH = 0; skewV = 0
        working = model.files.first.flatMap { try? ImageService.loadCGImage($0) }
        resetResizeFields(); updateEstimate()
    }
    private func rotate(_ q: Int) {
        if let w = working { working = ImageEditService.rotate(w, quarters: q); cropRects = []; selectionPx = nil; resetResizeFields(); updateEstimate() }
    }
    private func flip(h: Bool = false, v: Bool = false) {
        if let w = working { working = ImageEditService.flip(w, horizontal: h, vertical: v); updateEstimate() }
    }
    private func applyCrop() {
        guard let w = working, let r = cropRects.first else { return }
        working = ImageEditService.crop(w, normRect: r); cropRects = []; selectionPx = nil; resetResizeFields(); updateEstimate()
    }

    private func resetResizeFields() {
        guard let w = working else { return }
        if byPixels { hVal = Double(w.width); vVal = Double(w.height) } else { hVal = 100; vVal = 100 }
    }
    private func syncVertical() {
        guard let w = working else { return }
        vVal = byPixels ? (hVal * Double(w.height) / Double(max(1, w.width))).rounded() : hVal
    }
    private func applyResize() {
        guard let w = working else { return }
        let tw: Int, th: Int
        if byPixels {
            tw = Int(hVal)
            th = keepAspect ? Int((hVal * Double(w.height) / Double(max(1, w.width))).rounded()) : Int(vVal)
        } else {
            tw = Int((Double(w.width) * hVal / 100).rounded())
            th = Int((Double(w.height) * (keepAspect ? hVal : vVal) / 100).rounded())
        }
        working = ImageEditService.resizeExact(w, width: max(1, tw), height: max(1, th))
        resetResizeFields(); updateEstimate()
    }
    private func applySkew() {
        guard let w = working else { return }
        working = ImageEditService.skew(w, hDegrees: skewH, vDegrees: skewV)
        skewH = 0; skewV = 0; resetResizeFields(); updateEstimate()
    }

    private func updateSelection(_ norm: CGRect?) {
        guard let norm, let w = working else { selectionPx = nil; return }
        selectionPx = CGSize(width: (norm.width * CGFloat(w.width)).rounded(),
                             height: (norm.height * CGFloat(w.height)).rounded())
    }
    private func updateEstimate() {
        guard let out = working else { estimatedBytes = nil; return }
        estimatedBytes = ImageService.encodeData(finalCG(out), format: format, quality: quality)?.count
    }

    private func save() {
        guard let out = working, let src = model.files.first else { return }
        let url = OutputPath.make(for: src, dir: model.outputDir, suffix: "-edited", ext: format.ext)
        do { try ImageService.write(finalCG(out), to: url, format: format, quality: quality); saved = url }
        catch { model.error = error.localizedDescription }
    }

    private func label(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol).labelStyle(.titleAndIcon)
    }
    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.title2).bold()
            Text(s).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
