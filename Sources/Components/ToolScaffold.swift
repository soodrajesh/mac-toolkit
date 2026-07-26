import SwiftUI
import UniformTypeIdentifiers

/// Common tool layout: title, drop well, file list, output picker, options,
/// a run button, and a result/error bar. Views inject their own `options`
/// and `runLabel`/`onRun`. An optional `preview` builder renders a pane on the
/// right (image tools use it to show the image / a live result).
struct ToolScaffold<Options: View, Preview: View>: View {
    let title: String
    let subtitle: String
    @ObservedObject var model: JobModel
    let runLabel: String
    let onRun: () -> Void
    let previewVisible: Bool
    @ViewBuilder var preview: () -> Preview
    @ViewBuilder var options: () -> Options

    init(title: String, subtitle: String, model: JobModel, runLabel: String,
         onRun: @escaping () -> Void, previewVisible: Bool = true,
         @ViewBuilder preview: @escaping () -> Preview = { EmptyView() },
         @ViewBuilder options: @escaping () -> Options) {
        self.title = title; self.subtitle = subtitle; self.model = model
        self.runLabel = runLabel; self.onRun = onRun; self.previewVisible = previewVisible
        self.preview = preview; self.options = options
    }

    private var hasPreview: Bool { Preview.self != EmptyView.self && previewVisible }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.title2).bold()
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }

                    DropWell(model: model)
                    if !model.files.isEmpty { FileList(model: model) }
                    options()
                    OutputPicker(model: model)

                    HStack(spacing: 12) {
                        Button(action: onRun) {
                            if model.isRunning { ProgressView().controlSize(.small) }
                            else { Text(runLabel) }
                        }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(model.files.isEmpty || model.isRunning)
                        .buttonStyle(.borderedProminent)

                        if model.isRunning {
                            Button("Cancel") { model.cancel() }
                        } else if !model.files.isEmpty {
                            Button("Clear") { model.clear() }
                        }
                        Spacer()
                    }

                    if model.isRunning {
                        HStack(spacing: 8) {
                            ProgressView(value: model.progress).frame(width: 220)
                            Text("\(Int(model.progress * 100))%")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }

                    ResultBar(model: model)
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onReceive(NotificationCenter.default.publisher(for: .runTool)) { _ in
                if !model.isRunning, !model.files.isEmpty { onRun() }
            }

            if hasPreview {
                Divider()
                PreviewPane { preview() }
                    .frame(width: 380)
            }
        }
    }
}

/// Right-side preview container with a consistent header.
struct PreviewPane<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Preview", systemImage: "eye").font(.caption).foregroundStyle(.secondary)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A small "12 pages · 340 KB"-style caption shown under the file list once a
/// file is selected. `info` is a best-effort lookup (e.g. FileInfoService.*)
/// that may return nil while metadata can't be read.
struct MetadataLine: View {
    let text: String?
    var body: some View {
        if let text {
            Label(text, systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// A labeled details panel for the selected file's metadata (dimensions/EXIF,
/// PDF document properties, audio/video codec+bitrate+tags — see
/// FileInfoService.*Fields). Visible by default so it isn't easy to miss;
/// collapses to just a summary count once there's a lot to show.
struct MetadataPanel: View {
    let fields: [MetadataField]
    @State private var expanded = true

    var body: some View {
        if !fields.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(fields) { f in
                        HStack(alignment: .top, spacing: 8) {
                            Text(f.label).font(.caption).foregroundStyle(.secondary)
                                .frame(width: 92, alignment: .leading)
                            Text(f.value).font(.caption).textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.top, 6)
            } label: {
                Label("Details (\(fields.count))", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.08)))
            .frame(maxWidth: 460, alignment: .leading)
        }
    }
}

/// Reusable checkerboard-backed image preview (shows transparency).
struct ImagePreview: View {
    let image: NSImage?
    var caption: String? = nil
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.12))
                if let image {
                    Image(nsImage: image).resizable().scaledToFit().padding(6)
                } else {
                    Text("No image").foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 240)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
            if let caption { Text(caption).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// Drag-and-drop target plus a "Choose…" button.
struct DropWell: View {
    @ObservedObject var model: JobModel
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(model.allowsMultiple ? "Drop files here" : "Drop a file here")
                .foregroundStyle(.secondary)
            Button("Choose…") { choose() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(targeted ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : Color.gray.opacity(0.4))
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            handleDrop(providers); return true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFiles)) { _ in choose() }
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        let lock = NSLock()
        var collected: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); collected.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.add(collected) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = model.allowsMultiple
        panel.canChooseDirectories = model.allowsMultiple
        panel.canChooseFiles = true
        panel.allowedContentTypes = model.allowedTypes
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

/// Editable, reorderable list of selected files: numbered rows, selection
/// highlight, up/down reorder arrows (plus drag), a type icon, and remove.
struct FileList: View {
    @ObservedObject var model: JobModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(Array(model.files.enumerated()), id: \.element) { idx, url in
                    row(idx: idx, url: url)
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .frame(height: min(CGFloat(model.files.count) * 34 + 12, 220))
            .listStyle(.bordered)
        }
    }

    @ViewBuilder
    private func row(idx: Int, url: URL) -> some View {
        let isSel = model.selected == url
        HStack(spacing: 8) {
            if model.allowsMultiple {
                HStack(spacing: 2) {
                    Button { model.moveUp(url) } label: { Image(systemName: "arrow.up") }
                        .disabled(idx == 0)
                    Button { model.moveDown(url) } label: { Image(systemName: "arrow.down") }
                        .disabled(idx == model.files.count - 1)
                }
                .buttonStyle(.borderless).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(idx + 1).").font(.caption.monospacedDigit())
                .foregroundStyle(.secondary).frame(width: 22, alignment: .trailing)
            Image(systemName: icon(for: url)).foregroundStyle(isSel ? Color.white : .secondary)
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                .fontWeight(isSel ? .semibold : .regular)
                .foregroundStyle(isSel ? Color.white : .primary)
            Spacer()
            Text(url.fileSize.humanBytes).font(.caption)
                .foregroundStyle(isSel ? Color.white.opacity(0.85) : .secondary)
            Button { model.remove(url) } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(isSel ? Color.white.opacity(0.9) : .secondary)
        }
        .padding(.vertical, 4).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(isSel ? Color.accentColor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture { model.selected = isSel ? nil : url }
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
    }

    private func icon(for url: URL) -> String {
        if url.conformsTo(.pdf) { return "doc.richtext" }
        if url.conformsTo(.image) { return "photo" }
        if url.conformsTo(.movie) { return "film" }
        if url.conformsTo(.audio) { return "waveform" }
        return "doc"
    }
}

/// Output-folder chooser (default: next to source).
struct OutputPicker: View {
    @ObservedObject var model: JobModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Output:").foregroundStyle(.secondary)
            Text(model.outputDir?.path ?? "Same folder as source")
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

/// Shows errors, or a success summary with "Reveal in Finder".
struct ResultBar: View {
    @ObservedObject var model: JobModel

    var body: some View {
        Group {
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.08)))
            } else if let result = model.result {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(result.outputs.count) file\(result.outputs.count == 1 ? "" : "s") created",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    ForEach(result.messages, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                    ForEach(result.failures, id: \.self) {
                        Text($0).font(.caption).foregroundStyle(.orange)
                    }
                    if !result.outputs.isEmpty {
                        Button {
                            revealInFinder(result.outputs)
                        } label: { Label("Reveal in Finder", systemImage: "folder") }
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.07)))
            }
        }
    }
}
