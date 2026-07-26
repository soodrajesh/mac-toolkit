import SwiftUI
import UniformTypeIdentifiers

struct AudioLoopView: View {
    @StateObject private var model = JobModel(types: [.audio], multiple: false)
    @State private var clipDuration: Double?
    @State private var targetMinutes: String = "5"

    var body: some View {
        ToolScaffold(
            title: "Loop Audio",
            subtitle: "Repeat a short clip back-to-back until it fills a target duration. No crossfade at loop seams.",
            model: model,
            runLabel: "Loop",
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if let d = clipDuration {
                    Text("Clip length: \(String(format: "%.1f", d))s")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Text("Target duration (minutes)")
                    TextField("", text: $targetMinutes)
                        .frame(width: 80)
                        .textFieldStyle(.roundedBorder)
                }
                if let d = clipDuration, let minutes = Double(targetMinutes), minutes > 0, d > 0 {
                    let repeats = Int((minutes * 60 / d).rounded(.up))
                    Text("≈ \(repeats) repeat\(repeats == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: model.files) { _ in loadDuration() }
    }

    private func loadDuration() {
        clipDuration = nil
        guard let url = model.files.first else { return }
        Task.detached(priority: .userInitiated) {
            let d = try? AudioService.duration(of: url)
            await MainActor.run { clipDuration = d }
        }
    }

    private func run() {
        let dir = model.outputDir
        let minutesText = targetMinutes
        model.run { files in
            guard let url = files.first else { throw JobError.emptyInput }
            guard let minutes = Double(minutesText), minutes > 0 else {
                throw JobError.badInput("Enter a target duration greater than 0")
            }
            let out = OutputPath.make(for: url, dir: dir, suffix: "-looped", ext: "m4a")
            try AudioService.loop(url, targetDuration: minutes * 60, to: out)
            var r = JobResult()
            r.outputs.append(out)
            r.messages.append("Looped \(url.lastPathComponent) to \(minutesText) min → \(out.lastPathComponent)")
            return r
        }
    }
}
