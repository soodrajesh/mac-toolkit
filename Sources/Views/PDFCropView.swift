import SwiftUI
import UniformTypeIdentifiers

struct PDFCropView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var uniform = true
    @State private var all = 5.0
    @State private var left = 5.0
    @State private var right = 5.0
    @State private var top = 5.0
    @State private var bottom = 5.0
    @State private var pageImage: NSImage?
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Crop / Trim Margins",
            subtitle: "Trim whitespace margins from every page by a percentage of page size. Lossless — sets the PDF crop box, content underneath is untouched.",
            model: model,
            runLabel: "Crop",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MetadataPanel(fields: info)
                Toggle("Same margin on all sides", isOn: $uniform)
                if uniform {
                    HStack {
                        Text("Margin: \(Int(all))%")
                        Slider(value: $all, in: 0...30).frame(width: 220)
                    }
                } else {
                    marginSlider("Left", $left)
                    marginSlider("Right", $right)
                    marginSlider("Top", $top)
                    marginSlider("Bottom", $bottom)
                }
                Text("Percentage is of page width (left/right) or height (top/bottom).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in
            pageImage = model.files.first.flatMap { PDFService.renderPageImage($0, page: 0) }
            info = model.files.first.map { FileInfoService.pdfFields($0) } ?? []
        }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let pageImage {
                GeometryReader { geo in
                    let frame = fittedRect(imageSize: pageImage.size, in: geo.size)
                    let l = frame.width * CGFloat((uniform ? all : left) / 100)
                    let r = frame.width * CGFloat((uniform ? all : right) / 100)
                    let t = frame.height * CGFloat((uniform ? all : top) / 100)
                    let b = frame.height * CGFloat((uniform ? all : bottom) / 100)
                    let keptW = max(0, frame.width - l - r), keptH = max(0, frame.height - t - b)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: pageImage)
                            .resizable().scaledToFit()
                            .frame(width: geo.size.width, height: geo.size.height)
                        // Dimmed bands = trimmed area.
                        Rectangle().fill(.black.opacity(0.55))
                            .frame(width: frame.width, height: t)
                            .offset(x: frame.minX, y: frame.minY)
                        Rectangle().fill(.black.opacity(0.55))
                            .frame(width: frame.width, height: b)
                            .offset(x: frame.minX, y: frame.maxY - b)
                        Rectangle().fill(.black.opacity(0.55))
                            .frame(width: l, height: keptH)
                            .offset(x: frame.minX, y: frame.minY + t)
                        Rectangle().fill(.black.opacity(0.55))
                            .frame(width: r, height: keptH)
                            .offset(x: frame.maxX - r, y: frame.minY + t)
                        // Kept area outline.
                        Rectangle().strokeBorder(Color.accentColor, lineWidth: 2)
                            .frame(width: keptW, height: keptH)
                            .offset(x: frame.minX + l, y: frame.minY + t)
                    }
                }
                .frame(height: 360)
                .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
                Text("Dimmed area will be trimmed; the outlined area is what's kept.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drop a PDF to preview.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func fittedRect(imageSize s: CGSize, in c: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0 else { return .zero }
        let scale = min(c.width / s.width, c.height / s.height)
        let w = s.width * scale, h = s.height * scale
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }

    private func marginSlider(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text("\(label): \(Int(value.wrappedValue))%").frame(width: 90, alignment: .leading)
            Slider(value: value, in: 0...30).frame(width: 200)
        }
    }

    private func run() {
        let dir = model.outputDir
        let l = uniform ? all : left, r = uniform ? all : right
        let t = uniform ? all : top, b = uniform ? all : bottom
        model.run { files in
            var res = JobResult()
            for url in files {
                if Task.isCancelled { break }
                do {
                    let out = OutputPath.make(for: url, dir: dir, suffix: "-cropped", ext: "pdf")
                    try PDFService.cropMargins(url, left: l, right: r, top: t, bottom: b, to: out)
                    res.outputs.append(out)
                } catch {
                    res.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return res
        }
    }
}
