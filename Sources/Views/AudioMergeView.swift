import SwiftUI
import UniformTypeIdentifiers

struct AudioMergeView: View {
    @StateObject private var model = JobModel(types: [.audio])

    var body: some View {
        ToolScaffold(
            title: "Merge Audio",
            subtitle: "Combine multiple audio files into one, in list order. Drag rows to reorder.",
            model: model,
            runLabel: "Merge",
            onRun: run
        ) {
            EmptyView()
        }
    }

    private func run() {
        let dir = model.outputDir
        model.run { files in
            guard let first = files.first else { throw JobError.emptyInput }
            let out = OutputPath.make(for: first, dir: dir, suffix: "-merged", ext: "m4a")
            try AudioService.merge(files, to: out)
            var r = JobResult()
            r.outputs.append(out)
            r.messages.append("Merged \(files.count) files → \(out.lastPathComponent)")
            return r
        }
    }
}
