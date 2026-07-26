import SwiftUI
import UniformTypeIdentifiers

struct AudioMergeView: View {
    @StateObject private var model = JobModel(types: [.audio])
    @State private var info: String?

    var body: some View {
        ToolScaffold(
            title: "Merge Audio",
            subtitle: "Combine multiple audio files into one, in list order. Drag rows to reorder.",
            model: model,
            runLabel: "Merge",
            onRun: run
        ) {
            MetadataLine(text: info)
        }
        .onChange(of: model.files) { _ in updateInfo() }
    }

    private func updateInfo() {
        let files = model.files
        guard !files.isEmpty else { info = nil; return }
        Task.detached(priority: .userInitiated) {
            let totalDuration = files.reduce(0.0) { $0 + ((try? AudioService.duration(of: $1)) ?? 0) }
            let totalBytes = files.reduce(Int64(0)) { $0 + $1.fileSize }
            await MainActor.run {
                guard model.files == files else { return }
                info = "\(files.count) files · \(FileInfoService.formatDuration(totalDuration)) total · \(totalBytes.humanBytes) total"
            }
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
