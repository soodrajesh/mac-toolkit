import SwiftUI
import UniformTypeIdentifiers

struct VideoConvertView: View {
    @StateObject private var model = JobModel(types: [.movie])
    @State private var preset: VideoService.Preset = .hd1080
    @State private var thumbnail: NSImage?
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Convert & Compress Video",
            subtitle: "Batch: drop many videos to re-encode as MP4 at a target quality/resolution. Native AVFoundation; falls back to ffmpeg (if installed) for codecs like VP9/AV1 it can't re-encode.",
            model: model,
            runLabel: "Process",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Quality", selection: $preset) {
                    ForEach(VideoService.Preset.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("If a preset isn't compatible with a source file, it falls back to Highest Quality for that file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in loadPreview() }
        .onChange(of: model.selected) { _ in loadPreview() }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = model.focused {
                VideoPreviewPlayer(url: url, fallbackThumbnail: thumbnail)
                Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)

                if !info.isEmpty {
                    MetadataPanel(fields: info)
                }
            } else {
                Text("Drop a video to preview.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func loadPreview() {
        thumbnail = nil; info = []
        guard let url = model.focused else { return }
        info = FileInfoService.videoFields(url)
        Task.detached(priority: .userInitiated) {
            let img = FileInfoService.videoThumbnail(url)
            await MainActor.run {
                guard model.focused == url else { return }
                thumbnail = img
            }
        }
    }

    private func run() {
        let dir = model.outputDir
        let p = preset
        model.runWithProgress { files, report in
            var r = JobResult()
            let total = files.count
            for (i, url) in files.enumerated() {
                if Task.isCancelled { break }
                do {
                    let planned = OutputPath.make(for: url, dir: dir, suffix: "-\(p.rawValue.lowercased().replacingOccurrences(of: " ", with: ""))", ext: "mp4")
                    let out = try VideoService.convert(url, preset: p, to: planned, onProgress: { sub in
                        report((Double(i) + sub) / Double(total))
                    })
                    r.outputs.append(out)
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                report(Double(i + 1) / Double(total))
            }
            return r
        }
    }
}
