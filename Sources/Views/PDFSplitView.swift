import SwiftUI
import UniformTypeIdentifiers

struct PDFSplitView: View {
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var mode: Mode = .eachPage
    @State private var ranges = "1-3, 4-6"

    enum Mode: String, CaseIterable, Identifiable {
        case eachPage = "One file per page"
        case byRanges = "By page ranges"
        var id: String { rawValue }
    }

    var body: some View {
        ToolScaffold(
            title: "Split PDF",
            subtitle: "Break a PDF into separate files.",
            model: model,
            runLabel: "Split",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.radioGroup)

                if mode == .byRanges {
                    HStack {
                        Text("Ranges:")
                        TextField("e.g. 1-3, 5, 8-10", text: $ranges).frame(width: 220)
                    }
                    Text("Each range becomes its own file (1-based, inclusive).")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func run() {
        let dir = model.outputDir
        let m = mode
        let rangeText = ranges
        model.run { files in
            guard let url = files.first else { throw JobError.emptyInput }
            var outputs: [URL]
            switch m {
            case .eachPage:
                outputs = try PDFService.splitEachPage(url, dir: dir)
            case .byRanges:
                let parsed = PDFService.parseRanges(rangeText)
                guard !parsed.isEmpty else { throw JobError.badInput("No valid ranges") }
                outputs = try PDFService.split(url, ranges: parsed, dir: dir)
            }
            var r = JobResult()
            r.outputs = outputs
            r.messages.append("Created \(outputs.count) file\(outputs.count == 1 ? "" : "s")")
            return r
        }
    }
}
