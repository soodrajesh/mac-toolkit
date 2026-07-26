import SwiftUI
import UniformTypeIdentifiers

struct VideoExtractAudioView: View {
    @StateObject private var model = JobModel(types: [.movie])
    @State private var format: VideoService.AudioFormat = .m4a
    @State private var thumbnail: NSImage?
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Extract Audio",
            subtitle: "Batch: pull the audio track out of local video files. Native AVFoundation for M4A; MP3 uses ffmpeg (AVFoundation has no MP3 encoder).",
            model: model,
            runLabel: "Extract",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MetadataPanel(fields: info)
                Picker("Format", selection: $format) {
                    ForEach(VideoService.AudioFormat.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 220)
                if format == .mp3 && YtDlp.ffmpegPath == nil {
                    Label("MP3 needs ffmpeg — install with `brew install ffmpeg`, or choose M4A.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .onChange(of: model.files) { _ in loadPreview() }
        .onChange(of: model.selected) { _ in loadPreview() }
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let url = model.focused {
                VideoPreviewPlayer(url: url, fallbackThumbnail: thumbnail)
                Text("Audio will be extracted from this video.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Drop a video to preview.").font(.caption).foregroundStyle(.secondary)
            }
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
        let fmt = format
        model.runWithProgress { files, report in
            var r = JobResult()
            let total = files.count
            for (i, url) in files.enumerated() {
                if Task.isCancelled { break }
                do {
                    let planned = OutputPath.make(for: url, dir: dir, suffix: "-audio", ext: fmt.ext)
                    let out = try VideoService.extractAudio(url, format: fmt, to: planned, onProgress: { sub in
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
