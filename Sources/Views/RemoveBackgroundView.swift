import SwiftUI
import UniformTypeIdentifiers

struct RemoveBackgroundView: View {
    @StateObject private var model = JobModel(types: [.image])
    @State private var inputImage: NSImage?
    @State private var cutout: CGImage?         // cached transparent cutout
    @State private var cutoutURL: URL?          // which file the cutout is from
    @State private var previewImage: NSImage?

    @State private var mode: BgMode = .transparent
    @State private var bgColor: Color = .white
    @State private var bgImageURL: URL?
    @State private var bgImageCG: CGImage?
    @State private var info: [MetadataField] = []

    enum BgMode: String, CaseIterable, Identifiable {
        case transparent = "Transparent", color = "Solid color", image = "Image"
        var id: String { rawValue }
    }

    var body: some View {
        ToolScaffold(
            title: "Remove Background",
            subtitle: "One-click subject cutout, then keep it transparent or drop in a new background.",
            model: model,
            runLabel: "Remove Background",
            onRun: run,
            preview: { previewPane }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                MetadataPanel(fields: info)
                if !BackgroundService.isAvailable {
                    Label("Requires macOS 14 or later.", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }
                Picker("Background", selection: $mode) {
                    ForEach(BgMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 320)
                .onChange(of: mode) { _ in recomposite() }

                switch mode {
                case .transparent:
                    Label("Subject on a transparent PNG.", systemImage: "checkerboard.rectangle")
                        .font(.caption).foregroundStyle(.secondary)
                case .color:
                    HStack {
                        ColorPicker("Color", selection: $bgColor, supportsOpacity: false).fixedSize()
                            .onChange(of: bgColor) { _ in recomposite() }
                        ForEach(Array([Color.white, .black, .blue, .green, .red].enumerated()), id: \.offset) { _, c in
                            Button { bgColor = c; recomposite() } label: {
                                Circle().fill(c).frame(width: 16, height: 16).overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                            }.buttonStyle(.plain)
                        }
                    }
                case .image:
                    HStack {
                        Button("Choose background image…") { chooseBg() }
                        if let u = bgImageURL { Text(u.lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .onChange(of: model.files) { _ in reload() }
        .onChange(of: model.selected) { _ in reload() }
    }

    private func reload() {
        cutout = nil; cutoutURL = nil; previewImage = nil
        inputImage = model.focused.flatMap { NSImage(contentsOf: $0) }
        info = model.focused.map { FileInfoService.imageFields($0) } ?? []
    }

    private var previewPane: some View {
        VStack {
            ImagePreview(image: previewImage ?? inputImage,
                         caption: previewImage != nil ? "Result" : (model.focused?.lastPathComponent ?? "Drop an image"))
            Spacer()
        }
    }

    private func background() -> BackgroundService.Background {
        switch mode {
        case .transparent: return .transparent
        case .color: return .color(NSColor(bgColor))
        case .image: return bgImageCG.map { .image($0) } ?? .transparent
        }
    }

    /// Recomposites the cached cutout with the current background (no Vision re-run).
    private func recomposite() {
        guard let cut = cutout else { return }
        let out = BackgroundService.composite(cut, background: background())
        previewImage = NSImage(cgImage: out, size: NSSize(width: out.width, height: out.height))
    }

    private func chooseBg() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.canChooseFiles = true; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            bgImageURL = url
            bgImageCG = try? ImageService.loadCGImage(url)
            recomposite()
        }
    }

    private func run() {
        guard let url = model.focused else { model.error = "No image"; return }
        let bg = background()
        let ext = { if case .transparent = bg { return "png" } else { return "png" } }()
        let dir = model.outputDir
        let reuse = (cutoutURL == url) ? cutout : nil
        model.isRunning = true; model.error = nil; model.result = nil
        Task.detached(priority: .userInitiated) {
            do {
                let cut = try reuse ?? BackgroundService.cutout(url)
                let composed = BackgroundService.composite(cut, background: bg)
                let out = OutputPath.make(for: url, dir: dir, suffix: "-nobg", ext: ext)
                try ImageService.write(composed, to: out, format: .png, quality: 1)
                await MainActor.run {
                    cutout = cut; cutoutURL = url
                    previewImage = NSImage(cgImage: composed, size: NSSize(width: composed.width, height: composed.height))
                    var r = JobResult(); r.outputs.append(out); model.result = r
                    model.isRunning = false
                }
            } catch {
                await MainActor.run { model.error = error.localizedDescription; model.isRunning = false }
            }
        }
    }
}
