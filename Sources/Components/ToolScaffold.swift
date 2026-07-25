import SwiftUI
import UniformTypeIdentifiers

/// Common tool layout: title, drop well, file list, output picker, options,
/// a run button, and a result/error bar. Views inject their own `options`
/// and `runLabel`/`onRun`.
struct ToolScaffold<Options: View>: View {
    let title: String
    let subtitle: String
    @ObservedObject var model: JobModel
    let runLabel: String
    let onRun: () -> Void
    @ViewBuilder var options: () -> Options

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title2).bold()
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)

                if !model.files.isEmpty {
                    FileList(model: model)
                }

                options()

                OutputPicker(model: model)

                HStack(spacing: 12) {
                    Button(action: onRun) {
                        if model.isRunning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(runLabel)
                        }
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.files.isEmpty || model.isRunning)
                    .buttonStyle(.borderedProminent)

                    if !model.files.isEmpty {
                        Button("Clear") { model.clear() }
                            .disabled(model.isRunning)
                    }
                    Spacer()
                }

                ResultBar(model: model)
            }
            .padding(20)
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
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        var collected: [URL] = []
        let group = DispatchGroup()
        for p in providers {
            group.enter()
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { collected.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) { model.add(collected) }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = model.allowsMultiple
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = model.allowedTypes
        if panel.runModal() == .OK { model.add(panel.urls) }
    }
}

/// Editable, reorderable list of selected files.
struct FileList: View {
    @ObservedObject var model: JobModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(model.files.count) file\(model.files.count == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(model.files, id: \.self) { url in
                    HStack {
                        Image(systemName: "doc")
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(url.fileSize.humanBytes)
                            .font(.caption).foregroundStyle(.secondary)
                        Button {
                            model.remove(url)
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                }
                .onMove { model.move(from: $0, to: $1) }
            }
            .frame(height: min(CGFloat(model.files.count) * 30 + 12, 180))
            .listStyle(.bordered)
        }
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
