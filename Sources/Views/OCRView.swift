import SwiftUI
import UniformTypeIdentifiers

struct OCRView: View {
    enum Output: String, CaseIterable, Identifiable {
        case text = "Extract text"
        case searchablePDF = "Searchable PDF"
        var id: String { rawValue }
    }

    @StateObject private var model = JobModel(types: [.pdf, .image], multiple: false)
    @State private var text = ""
    @State private var output: Output = .text
    @State private var pdfResult: URL?
    @State private var info: [MetadataField] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OCR / Text").font(.title2).bold()
                    Text("Extract text, or produce a searchable PDF (on-device, Vision).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }
                MetadataPanel(fields: info)

                Picker("Output", selection: $output) {
                    ForEach(Output.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 280)

                HStack(spacing: 12) {
                    Button(action: run) {
                        if model.isRunning { ProgressView().controlSize(.small) }
                        else { Text(output == .text ? "Recognize Text" : "Build Searchable PDF") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.files.isEmpty || model.isRunning)

                    if output == .text && !text.isEmpty {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                        Button(action: save) { Label("Save .txt", systemImage: "square.and.arrow.down") }
                    }
                    Spacer()
                }

                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }

                if let pdfResult {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Searchable PDF created", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Button { revealInFinder([pdfResult]) } label: {
                            Label("Reveal in Finder", systemImage: "folder")
                        }.controlSize(.small)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.07)))
                }

                if output == .text && !text.isEmpty {
                    TextEditor(text: .constant(text))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.3)))
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in
            guard let first = model.files.first else { info = []; return }
            info = first.conformsTo(.pdf) ? FileInfoService.pdfFields(first) : FileInfoService.imageFields(first)
        }
    }

    private func run() {
        guard let url = model.files.first else { return }
        model.isRunning = true; model.error = nil; text = ""; pdfResult = nil
        let mode = output
        let dir = model.outputDir
        Task.detached(priority: .userInitiated) {
            do {
                switch mode {
                case .text:
                    let result = url.conformsTo(.pdf)
                        ? try OCRService.recognizePDF(url)
                        : try OCRService.recognizeImageFile(url)
                    await MainActor.run { text = result; model.isRunning = false }
                case .searchablePDF:
                    let out = OutputPath.make(for: url, dir: dir, suffix: "-searchable", ext: "pdf")
                    try OCRService.makeSearchablePDF(url, to: out)
                    await MainActor.run { pdfResult = out; model.isRunning = false }
                }
            } catch {
                await MainActor.run { model.error = error.localizedDescription; model.isRunning = false }
            }
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = (model.files.first?.deletingPathExtension().lastPathComponent ?? "ocr") + ".txt"
        if panel.runModal() == .OK, let url = panel.url {
            try? text.write(to: url, atomically: true, encoding: .utf8)
            revealInFinder([url])
        }
    }
}
