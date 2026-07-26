import SwiftUI
import UniformTypeIdentifiers

struct PDFMetadataView: View {
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var meta = PDFService.Meta()
    @State private var saved: URL?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PDF Metadata").font(.title2).bold()
                    Text("View and edit a PDF's title, author, subject, keywords, and creator.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }

                if !model.files.isEmpty {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            field("Title", $meta.title)
                            field("Author", $meta.author)
                            field("Subject", $meta.subject)
                            field("Keywords", $meta.keywords, hint: "comma-separated")
                            field("Creator", $meta.creator)
                        }.padding(6)
                    } label: { Label("Document Info", systemImage: "info.circle").font(.callout).bold() }
                    .frame(maxWidth: 520, alignment: .leading)

                    HStack(spacing: 10) {
                        Button("Save") { save() }.buttonStyle(.borderedProminent)
                        Button("Reload") { load() }
                        if let saved {
                            Button { revealInFinder([saved]) } label: {
                                Label("Saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                            }.foregroundStyle(.green)
                        }
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                OutputPicker(model: model)
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in load() }
    }

    private func field(_ label: String, _ text: Binding<String>, hint: String = "") -> some View {
        HStack {
            Text(label).frame(width: 80, alignment: .trailing).foregroundStyle(.secondary)
            TextField(hint, text: text).textFieldStyle(.roundedBorder).frame(width: 340)
        }
    }

    private func load() {
        saved = nil; model.error = nil
        guard let url = model.files.first else { meta = .init(); return }
        meta = PDFService.readMetadata(url)
    }

    private func save() {
        guard let url = model.files.first else { return }
        do {
            let out = OutputPath.make(for: url, dir: model.outputDir, suffix: "-meta", ext: "pdf")
            try PDFService.writeMetadata(url, meta, to: out); saved = out
        } catch { model.error = error.localizedDescription }
    }
}
