import SwiftUI
import UniformTypeIdentifiers

struct PDFMergeView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var info: String?

    var body: some View {
        ToolScaffold(
            title: "Merge PDF",
            subtitle: "Combine multiple PDFs into one. Drag rows to reorder.",
            model: model,
            runLabel: "Merge",
            onRun: run
        ) {
            MetadataLine(text: info)
        }
        .onChange(of: model.files) { _ in updateInfo() }
    }

    private func updateInfo() {
        guard !model.files.isEmpty else { info = nil; return }
        let totalPages = model.files.reduce(0) { $0 + PDFService.pageCount($1) }
        let totalBytes = model.files.reduce(Int64(0)) { $0 + $1.fileSize }
        info = "\(model.files.count) file\(model.files.count == 1 ? "" : "s") · \(totalPages) page\(totalPages == 1 ? "" : "s") total · \(totalBytes.humanBytes) total"
    }

    private func run() {
        let dir = model.outputDir
        model.run { files in
            guard let first = files.first else { throw JobError.emptyInput }
            let out = OutputPath.make(for: first, dir: dir, suffix: "-merged", ext: "pdf")
            try PDFService.merge(files, to: out)
            var r = JobResult()
            r.outputs.append(out)
            r.messages.append("Merged \(files.count) files → \(out.lastPathComponent)")
            return r
        }
    }
}
