import SwiftUI
import UniformTypeIdentifiers

struct PDFPageNumbersView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var format = "Page {n}"
    @State private var position: PDFService.StampPosition = .bottomCenter
    @State private var startAt = 1
    @State private var fontSize = 12.0

    var body: some View {
        ToolScaffold(
            title: "Page Numbers",
            subtitle: "Stamp page numbers or a label on every page.",
            model: model,
            runLabel: "Add Numbers",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Format:")
                    TextField("Page {n}", text: $format).frame(width: 200)
                }
                Text("Use {n} for the page number and {total} for the count — e.g. \"{n} / {total}\".")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Position", selection: $position) {
                    ForEach(PDFService.StampPosition.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 260)
                Stepper("Start at: \(startAt)", value: $startAt, in: 0...9999).frame(width: 200)
                HStack {
                    Text("Font size: \(Int(fontSize))")
                    Slider(value: $fontSize, in: 8...36, step: 1).frame(width: 180)
                }
            }
        }
    }

    private func run() {
        let fmt = format, pos = position, start = startAt, fs = fontSize
        let dir = model.outputDir
        model.run { files in
            var r = JobResult()
            for url in files {
                do {
                    let out = OutputPath.make(for: url, dir: dir, suffix: "-numbered", ext: "pdf")
                    try PDFService.addPageNumbers(url, format: fmt, position: pos, startAt: start,
                                                 fontSize: CGFloat(fs), to: out)
                    r.outputs.append(out)
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return r
        }
    }
}
