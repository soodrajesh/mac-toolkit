import SwiftUI
import UniformTypeIdentifiers

struct PDFPagesView: View {
    @StateObject private var model = JobModel(types: [.pdf, .image])
    @State private var op: Op = .rotate
    @State private var rotation = 90
    @State private var pageSpec = "1, 3-5"
    @State private var dpi = 150.0
    @State private var imgFormat: ImageService.Format = .png
    @State private var quality = 0.8

    enum Op: String, CaseIterable, Identifiable {
        case rotate = "Rotate"
        case delete = "Delete pages"
        case extract = "Extract pages"
        case toImages = "PDF → Images"
        case fromImages = "Images → PDF"
        var id: String { rawValue }
    }

    var body: some View {
        ToolScaffold(
            title: "PDF Pages",
            subtitle: "Rotate, delete, extract pages, or convert between PDF and images.",
            model: model,
            runLabel: runLabel,
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Operation", selection: $op) {
                    ForEach(Op.allCases) { Text($0.rawValue).tag($0) }
                }

                switch op {
                case .rotate:
                    Picker("Rotate by", selection: $rotation) {
                        Text("90° CW").tag(90); Text("180°").tag(180); Text("270° CW").tag(270)
                    }.pickerStyle(.segmented).frame(width: 260)
                case .delete, .extract:
                    HStack {
                        Text("Pages:")
                        TextField("e.g. 1, 3-5", text: $pageSpec).frame(width: 200)
                    }
                case .toImages:
                    HStack {
                        Text("\(Int(dpi)) dpi"); Slider(value: $dpi, in: 72...300, step: 12).frame(width: 160)
                    }
                    Picker("Format", selection: $imgFormat) {
                        Text("PNG").tag(ImageService.Format.png); Text("JPEG").tag(ImageService.Format.jpeg)
                    }.pickerStyle(.segmented).frame(width: 200)
                case .fromImages:
                    Text("Add image files above; they become one PDF (in listed order).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var runLabel: String {
        switch op {
        case .rotate: return "Rotate"; case .delete: return "Delete"
        case .extract: return "Extract"; case .toImages: return "Export Images"
        case .fromImages: return "Build PDF"
        }
    }

    private func run() {
        let dir = model.outputDir
        let operation = op, rot = rotation, spec = pageSpec
        let d = dpi, fmt = imgFormat, q = quality
        model.run { files in
            var r = JobResult()
            switch operation {
            case .fromImages:
                let imgs = files.filter { $0.conformsTo(.image) }
                guard let first = imgs.first else { throw JobError.badInput("No images selected") }
                let out = OutputPath.make(for: first, dir: dir, suffix: "-images", ext: "pdf")
                try PDFService.fromImages(imgs, to: out)
                r.outputs.append(out)
                r.messages.append("Built PDF from \(imgs.count) images")
            default:
                let pdfs = files.filter { $0.conformsTo(.pdf) }
                guard !pdfs.isEmpty else { throw JobError.badInput("No PDF selected") }
                for url in pdfs {
                    do {
                        switch operation {
                        case .rotate:
                            let out = OutputPath.make(for: url, dir: dir, suffix: "-rotated", ext: "pdf")
                            try PDFService.rotate(url, degrees: rot, to: out)
                            r.outputs.append(out)
                        case .delete:
                            let out = OutputPath.make(for: url, dir: dir, suffix: "-edited", ext: "pdf")
                            let pages = Set(PDFService.parseRanges(spec).flatMap { Array($0.0...$0.1) })
                            try PDFService.delete(url, pages: pages, to: out)
                            r.outputs.append(out)
                        case .extract:
                            let out = OutputPath.make(for: url, dir: dir, suffix: "-extracted", ext: "pdf")
                            let pages = PDFService.parseRanges(spec).flatMap { Array($0.0...$0.1) }
                            try PDFService.extract(url, pages: pages, to: out)
                            r.outputs.append(out)
                        case .toImages:
                            let outs = try PDFService.toImages(url, dpi: d, format: fmt, quality: q, dir: dir)
                            r.outputs.append(contentsOf: outs)
                            r.messages.append("\(url.lastPathComponent): \(outs.count) images")
                        case .fromImages: break
                        }
                    } catch {
                        r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    }
                }
            }
            return r
        }
    }
}
