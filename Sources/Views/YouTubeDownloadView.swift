import SwiftUI

struct YouTubeDownloadView: View {
    enum Mode { case video, audio }

    @StateObject private var model = DownloadQueueModel()
    @State private var pastedURLs = ""
    @State private var mode: Mode = .video
    @State private var videoQuality: YtDlp.VideoQuality = .p720
    @State private var audioBitrate: YtDlp.AudioBitrate = .kbps192
    @State private var completedOutputs: [URL] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Video Downloader").font(.title2).bold()
                    Text("Batch download videos from any site as MP4 or extract audio as MP3.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if YtDlp.isAvailable {
                    Label("yt-dlp + ffmpeg ready", systemImage: "checkmark.seal")
                        .font(.caption).foregroundStyle(.green)
                } else {
                    Label("yt-dlp/ffmpeg not found — install with `brew install yt-dlp ffmpeg`",
                          systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste video URLs (one per line)").font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $pastedURLs)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))

                    HStack {
                        Button("Add to Queue") {
                            model.addURLs(from: pastedURLs)
                            pastedURLs = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pastedURLs.trimmingCharacters(in: .whitespaces).isEmpty)
                        Spacer()
                    }
                }

                if !model.items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Queue: \(model.items.count) URL\(model.items.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear All") { model.clear() }
                                .controlSize(.small)
                                .disabled(model.isRunning)
                        }

                        VStack(spacing: 4) {
                            ForEach($model.items) { $item in
                                queueRow(item: $item)
                            }
                        }
                        .frame(maxHeight: min(CGFloat(model.items.count) * 56 + 8, 250))
                    }
                }

                Picker("Format", selection: $mode) {
                    Text("Video (MP4)").tag(Mode.video)
                    Text("Audio (MP3)").tag(Mode.audio)
                }.pickerStyle(.segmented).frame(width: 200)

                if mode == .video {
                    Picker("Quality", selection: $videoQuality) {
                        ForEach(YtDlp.VideoQuality.allCases) { q in
                            Text(q.label).tag(q)
                        }
                    }
                    .frame(width: 200)
                } else {
                    Picker("Bitrate", selection: $audioBitrate) {
                        ForEach(YtDlp.AudioBitrate.allCases) { b in
                            Text(b.label).tag(b)
                        }
                    }
                    .frame(width: 160)
                }

                OutputFolderPicker(model: model)

                HStack(spacing: 12) {
                    let hasPastedText = !pastedURLs.trimmingCharacters(in: .whitespaces).isEmpty
                    let hasQueuedItems = !model.items.isEmpty

                    if model.isRunning {
                        Button(action: { model.cancel() }) {
                            Text("Cancel")
                        }
                        .keyboardShortcut(.escape)
                        .buttonStyle(.borderedProminent)
                        .foregroundStyle(.red)
                    } else {
                        Button(action: runDownloads) {
                            Text("Download")
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(!YtDlp.isAvailable || (!hasPastedText && !hasQueuedItems))
                        .buttonStyle(.borderedProminent)
                    }

                    if !completedOutputs.isEmpty {
                        Button("Reveal in Finder") {
                            revealInFinder(completedOutputs)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer()
                }

                summaryBar()
            }
            .padding(20)
        }
        .onReceive(NotificationCenter.default.publisher(for: .runTool)) { _ in
            if !model.isRunning && !model.items.isEmpty && YtDlp.isAvailable {
                runDownloads()
            }
        }
    }

    @ViewBuilder
    private func queueRow(item: Binding<QueueItem>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                switch item.status.wrappedValue {
                case .queued:
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                case .downloading:
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20)
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                case .failed:
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .frame(width: 20)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.sourceURL.wrappedValue)
                        .lineLimit(1).truncationMode(.middle)
                        .font(.callout)
                    if case .downloading(let progress, let size) = item.status.wrappedValue {
                        HStack(spacing: 12) {
                            ProgressView(value: progress)
                            Text(String(format: "%.1f%%", progress * 100))
                                .font(.caption).foregroundStyle(.secondary)
                            if !size.isEmpty {
                                Text(size)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else if case .failed(let msg) = item.status.wrappedValue {
                        Text(msg).font(.caption).foregroundStyle(.orange).lineLimit(2)
                    }
                }

                Spacer()

                Button {
                    model.remove(item.wrappedValue.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(model.isRunning)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color.gray.opacity(0.05)))
    }

    @ViewBuilder
    private func summaryBar() -> some View {
        let done = model.items.filter { if case .done = $0.status { return true } else { return false } }.count
        let failed = model.items.filter { if case .failed = $0.status { return true } else { return false } }.count

        if done > 0 || failed > 0 {
            VStack(alignment: .leading, spacing: 6) {
                if failed == 0 {
                    Label("\(done) file\(done == 1 ? "" : "s") downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("\(done) done, \(failed) failed", systemImage: done > 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(done > 0 ? .green : .red)
                }
                if !completedOutputs.isEmpty {
                    Button {
                        revealInFinder(completedOutputs)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(failed == 0 ? Color.green.opacity(0.07) : Color.orange.opacity(0.07)))
        }
    }

    private func runDownloads() {
        completedOutputs = []
        let format: YtDlp.Format = mode == .video ? .mp4(videoQuality) : .mp3(audioBitrate)

        let trimmedText = pastedURLs.trimmingCharacters(in: .whitespaces)
        if !trimmedText.isEmpty && model.items.isEmpty {
            model.addURLs(from: trimmedText)
            pastedURLs = ""
        }

        model.run(format: format)

        Task {
            while model.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            completedOutputs = model.items.compactMap { item in
                if case .done(let url) = item.status { return url } else { return nil }
            }
        }
    }
}

struct OutputFolderPicker: View {
    @ObservedObject var model: DownloadQueueModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Output:").foregroundStyle(.secondary)
            Text(model.outputDir?.path ?? "Downloads folder")
                .lineLimit(1).truncationMode(.middle)
                .foregroundStyle(model.outputDir == nil ? .secondary : .primary)
            Spacer()
            Button("Change…") { chooseDir() }.controlSize(.small)
            if model.outputDir != nil {
                Button("Reset") { model.outputDir = nil }.controlSize(.small)
            }
        }
        .font(.callout)
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { model.outputDir = panel.url }
    }
}
