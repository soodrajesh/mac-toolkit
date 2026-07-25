import SwiftUI
import UniformTypeIdentifiers

struct RemoveBackgroundView: View {
    @StateObject private var model = JobModel(types: [.image])

    var body: some View {
        ToolScaffold(
            title: "Remove Background",
            subtitle: "One-click subject cutout to a transparent PNG (on-device).",
            model: model,
            runLabel: "Remove Background",
            onRun: run
        ) {
            if !BackgroundService.isAvailable {
                Label("Requires macOS 14 or later.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Uses Apple's Vision subject-detection. Best on photos with a clear subject.",
                      systemImage: "wand.and.stars").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func run() {
        let dir = model.outputDir
        model.run { files in
            var r = JobResult()
            for url in files {
                do {
                    let out = OutputPath.make(for: url, dir: dir, suffix: "-nobg", ext: "png")
                    try BackgroundService.removeBackground(url, to: out)
                    r.outputs.append(out)
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return r
        }
    }
}
