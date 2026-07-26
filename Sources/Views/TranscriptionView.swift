import SwiftUI
import Speech
import UniformTypeIdentifiers

struct TranscriptionView: View {
    @StateObject private var model = JobModel(types: [.audio, .movie])
    @State private var locales: [Locale] = []
    @State private var locale = Locale(identifier: "en-US")
    @State private var authStatus = TranscriptionService.authorizationStatus
    @State private var exportSRT = false
    @State private var info: [MetadataField] = []

    var body: some View {
        ToolScaffold(
            title: "Transcribe",
            subtitle: "Batch: on-device speech-to-text for audio or video files. Nothing leaves your Mac — transcription that can't run fully offline for a language is refused rather than sent to a server.",
            model: model,
            runLabel: "Transcribe",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 12) {
                MetadataPanel(fields: info)
                authorizationBanner

                if locales.isEmpty {
                    ProgressView("Checking on-device languages…").controlSize(.small)
                } else {
                    Picker("Language", selection: $locale) {
                        ForEach(locales, id: \.identifier) { loc in
                            Text(Locale.current.localizedString(forIdentifier: loc.identifier) ?? loc.identifier)
                                .tag(loc)
                        }
                    }.frame(width: 320)
                }

                Toggle("Also export .srt subtitles (approximate timing)", isOn: $exportSRT)
                Text("Video files: the audio track is extracted first, then transcribed. Output is a .txt file next to each source.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: model.files) { _ in
            guard let url = model.files.first else { info = []; return }
            info = url.conformsTo(.movie) ? FileInfoService.videoFields(url) : FileInfoService.audioFields(url)
        }
        .task {
            let found = await Task.detached(priority: .userInitiated) { TranscriptionService.onDeviceLocales() }.value
            // This app only needs English (US/UK/India) — narrow the picker to those
            // rather than showing every on-device-supported locale.
            let wantedRegions = ["US", "GB", "IN"]
            let english = found.filter { $0.language.languageCode?.identifier == "en" }
            let filtered = wantedRegions.compactMap { region in english.first { $0.region?.identifier == region } }
            locales = filtered.isEmpty ? found : filtered
            if !locales.contains(where: { $0.identifier == locale.identifier }), let first = locales.first {
                locale = first
            }
        }
    }

    @ViewBuilder
    private var authorizationBanner: some View {
        switch authStatus {
        case .authorized:
            EmptyView()
        case .notDetermined:
            HStack {
                Label("Speech recognition needs one-time permission.", systemImage: "waveform.circle")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enable…") { Task { authStatus = await TranscriptionService.requestAuthorization() } }
                    .controlSize(.small)
            }
        case .denied, .restricted:
            Label("Speech recognition is disabled for this app — enable it under System Settings → Privacy & Security → Speech Recognition.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        @unknown default:
            EmptyView()
        }
    }

    private func run() {
        if authStatus == .notDetermined {
            Task {
                authStatus = await TranscriptionService.requestAuthorization()
                if authStatus == .authorized { performRun() }
                else { model.error = "Speech Recognition permission is required to transcribe." }
            }
            return
        }
        guard authStatus == .authorized else {
            model.error = "Speech Recognition is disabled for this app — enable it under System Settings → Privacy & Security → Speech Recognition."
            return
        }
        performRun()
    }

    private func performRun() {
        let dir = model.outputDir
        let loc = locale
        let withSRT = exportSRT
        model.runWithProgress { files, report in
            var r = JobResult()
            let total = files.count
            for (i, url) in files.enumerated() {
                if Task.isCancelled { break }
                let base = Double(i) / Double(total), span = 1.0 / Double(total)
                do {
                    let isVideo = url.conformsTo(.movie)
                    var audioURL = url
                    var tempFile: URL?
                    if isVideo {
                        let tmp = OutputPath.temp(ext: "m4a")
                        audioURL = try VideoService.extractAudio(url, format: .m4a, to: tmp, onProgress: { sub in
                            report(base + span * sub * 0.3)
                        })
                        tempFile = tmp
                    }
                    let result = try TranscriptionService.transcribe(audioURL, locale: loc, onProgress: { sub in
                        let floor = isVideo ? 0.3 : 0.0
                        let scale = isVideo ? 0.7 : 1.0
                        report(base + span * (floor + scale * sub))
                    })
                    if let tempFile { try? FileManager.default.removeItem(at: tempFile) }

                    let txtOut = OutputPath.make(for: url, dir: dir, suffix: "-transcript", ext: "txt")
                    try result.text.write(to: txtOut, atomically: true, encoding: .utf8)
                    r.outputs.append(txtOut)
                    let words = result.text.split(separator: " ").count
                    r.messages.append("\(url.lastPathComponent): \(words) words")

                    if withSRT {
                        let srtOut = OutputPath.make(for: url, dir: dir, suffix: "-transcript", ext: "srt")
                        try TranscriptionService.srt(from: result.segments).write(to: srtOut, atomically: true, encoding: .utf8)
                        r.outputs.append(srtOut)
                    }
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
                report(Double(i + 1) / Double(total))
            }
            return r
        }
    }
}
