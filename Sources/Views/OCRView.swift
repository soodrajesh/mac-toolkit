import SwiftUI
import UniformTypeIdentifiers

struct OCRView: View {
    @StateObject private var model = JobModel(types: [.pdf, .image], multiple: false)
    @State private var text = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("OCR / Text").font(.title2).bold()
                    Text("Extract text from scanned PDFs or images (on-device, Vision).")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                HStack(spacing: 12) {
                    Button(action: run) {
                        if model.isRunning { ProgressView().controlSize(.small) }
                        else { Text("Recognize Text") }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.files.isEmpty || model.isRunning)

                    if !text.isEmpty {
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

                if !text.isEmpty {
                    TextEditor(text: .constant(text))
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 260)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.3)))
                }
            }
            .padding(20)
        }
    }

    private func run() {
        guard let url = model.files.first else { return }
        model.isRunning = true; model.error = nil; text = ""
        Task.detached(priority: .userInitiated) {
            do {
                let result: String
                if url.conformsTo(.pdf) {
                    result = try OCRService.recognizePDF(url)
                } else {
                    result = try OCRService.recognizeImageFile(url)
                }
                await MainActor.run { text = result; model.isRunning = false }
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
