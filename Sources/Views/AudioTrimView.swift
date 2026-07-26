import SwiftUI
import UniformTypeIdentifiers

struct AudioTrimView: View {
    @StateObject private var model = JobModel(types: [.audio], multiple: false)
    @StateObject private var player = AudioPlayerController()
    @State private var duration: Double = 0
    @State private var peaks: [Float] = []
    @State private var regions: [CutRegion] = []
    @State private var selectedID: CutRegion.ID?
    @State private var mode: AudioService.ExtractMode = .extract
    @State private var loadError: String?
    @State private var info: [MetadataField] = []

    private static let bucketCount = 400

    var body: some View {
        ToolScaffold(
            title: "Trim Audio",
            subtitle: "Drag on the waveform to create one or more cut regions. Pinch to zoom for precision.",
            model: model,
            runLabel: mode == .extract ? "Extract" : "Delete & Merge",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MetadataPanel(fields: info)
                if duration > 0 {
                    WaveformView(peaks: peaks, duration: duration, regions: $regions,
                                 selectedID: $selectedID, playheadTime: player.currentTime,
                                 onSeek: { player.seek(to: $0) })

                    playbackBar

                    Picker("Mode", selection: $mode) {
                        Text("Extract Selected").tag(AudioService.ExtractMode.extract)
                        Text("Delete Selected").tag(AudioService.ExtractMode.delete)
                    }
                    .pickerStyle(.segmented).frame(width: 320)

                    regionInspector

                    Text("\(regions.count) region\(regions.count == 1 ? "" : "s") selected")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let err = loadError {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                } else if !model.files.isEmpty {
                    Text("Loading waveform…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.files) { _ in loadFile() }
    }

    private var playbackBar: some View {
        HStack(spacing: 10) {
            Button(action: player.togglePlayPause) {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
            }
            .buttonStyle(.borderless)
            Text("\(format(player.currentTime)) / \(format(duration))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var regionInspector: some View {
        if let binding = selectedRegionBinding {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Cut from:")
                    TextField("start", text: timeBinding(binding, isStart: true)).frame(width: 80)
                    Text("to")
                    TextField("end", text: timeBinding(binding, isStart: false)).frame(width: 80)
                    Button(role: .destructive) {
                        regions.removeAll { $0.id == binding.id }
                        selectedID = nil
                    } label: {
                        Image(systemName: "trash")
                    }
                }
                .textFieldStyle(.roundedBorder)

                HStack(spacing: 16) {
                    Toggle("Fade in", isOn: binding.fadeIn).disabled(mode == .delete)
                    Toggle("Fade out", isOn: binding.fadeOut).disabled(mode == .delete)
                }
                .toggleStyle(.checkbox)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.08)))
        } else {
            Text("Select a region (or drag on the waveform to create one) to edit its bounds.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var selectedRegionBinding: Binding<CutRegion>? {
        guard let id = selectedID, let idx = regions.firstIndex(where: { $0.id == id }) else { return nil }
        return $regions[idx]
    }

    private func timeBinding(_ region: Binding<CutRegion>, isStart: Bool) -> Binding<String> {
        Binding<String>(
            get: { format(isStart ? region.wrappedValue.range.lowerBound : region.wrappedValue.range.upperBound) },
            set: { newValue in
                guard let secs = parseTime(newValue) else { return }
                if isStart {
                    let newStart = min(max(secs, 0), region.wrappedValue.range.upperBound - 0.05)
                    region.wrappedValue.range = newStart...region.wrappedValue.range.upperBound
                } else {
                    let newEnd = max(min(secs, duration), region.wrappedValue.range.lowerBound + 0.05)
                    region.wrappedValue.range = region.wrappedValue.range.lowerBound...newEnd
                }
            }
        )
    }

    private func format(_ seconds: Double) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%05.2f", Int(s) / 60, s.truncatingRemainder(dividingBy: 60))
    }

    /// Parses "M:SS.ss" (or a plain seconds value) back into seconds.
    private func parseTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":")
        if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) {
            return m * 60 + s
        }
        return Double(text)
    }

    private func loadFile() {
        duration = 0; peaks = []; regions = []; selectedID = nil; loadError = nil; info = []
        player.stop()
        guard let url = model.files.first else { return }
        player.load(url: url)
        let bucketCount = Self.bucketCount
        Task.detached(priority: .userInitiated) {
            do {
                let d = try AudioService.duration(of: url)
                let p = try AudioService.peaks(of: url, bucketCount: bucketCount)
                let fields = FileInfoService.audioFields(url)
                await MainActor.run {
                    duration = d
                    peaks = p
                    info = fields
                }
            } catch {
                await MainActor.run { loadError = error.localizedDescription }
            }
        }
    }

    private func run() {
        let dir = model.outputDir
        let regs = regions
        let m = mode
        let dur = duration
        model.run { files in
            guard let url = files.first else { throw JobError.emptyInput }
            let suffix = m == .extract ? "-extracted" : "-cut"
            let out = OutputPath.make(for: url, dir: dir, suffix: suffix, ext: "m4a")
            try AudioService.exportRegions(url, regions: regs, mode: m, duration: dur, to: out)
            var r = JobResult()
            r.outputs.append(out)
            let verb = m == .extract ? "Extracted" : "Cut"
            r.messages.append("\(verb) \(regs.count) region\(regs.count == 1 ? "" : "s") → \(out.lastPathComponent)")
            return r
        }
    }
}
