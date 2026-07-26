import SwiftUI
import UniformTypeIdentifiers

struct QRCodeView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case generate = "Generate"
        case read = "Read"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .generate

    // Generate
    @State private var text = "https://github.com/soodrajesh"
    @State private var size = 512
    @State private var barcodeType: QRService.BarcodeType = .qr
    @State private var preview: NSImage?

    // Read
    @StateObject private var readModel = JobModel(types: [.image], multiple: false)
    @State private var payloads: [QRService.Decoded] = []
    @State private var readError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Barcode / QR").font(.title2).bold()
                    Text("Generate a QR/Code 128/PDF417/Aztec barcode, or read any barcode from an image.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 240)

                if mode == .generate { generateView } else { readView }
            }
            .padding(20)
        }
    }

    private var generateView: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Content").font(.callout).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))
            }
            Picker("Type", selection: $barcodeType) {
                ForEach(QRService.BarcodeType.allCases) { Text($0.rawValue).tag($0) }
            }.frame(width: 240)
            Picker("Size", selection: $size) {
                Text("256 px").tag(256); Text("512 px").tag(512); Text("1024 px").tag(1024)
            }.frame(width: 200)

            HStack {
                Button("Preview") { renderPreview() }
                Button("Save PNG…") { save() }.buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                Spacer()
            }

            if let preview {
                Image(nsImage: preview)
                    .interpolation(.none)
                    .resizable().scaledToFit()
                    .frame(width: 220, height: 220)
                    .background(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.3)))
            }
        }
    }

    private var readView: some View {
        VStack(alignment: .leading, spacing: 14) {
            DropWell(model: readModel)
            if !readModel.files.isEmpty { FileList(model: readModel) }
            Button("Decode") { decode() }
                .buttonStyle(.borderedProminent)
                .disabled(readModel.files.isEmpty)

            if let readError {
                Label(readError, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            ForEach(payloads.indices, id: \.self) { i in
                let decoded = payloads[i]
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(decoded.payload).textSelection(.enabled)
                            .font(.system(.body, design: .monospaced))
                        Text(decoded.symbology).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(decoded.payload, forType: .string)
                    } label: { Image(systemName: "doc.on.doc") }.buttonStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).fill(.gray.opacity(0.08)))
            }
        }
    }

    private func renderPreview() {
        guard let cg = QRService.generate(text, size: size, type: barcodeType) else { preview = nil; return }
        preview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func save() {
        guard let cg = QRService.generate(text, size: size, type: barcodeType) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "barcode.png"
        if panel.runModal() == .OK, let url = panel.url {
            try? ImageService.write(cg, to: url, format: .png, quality: 1)
            revealInFinder([url])
        }
    }

    private func decode() {
        guard let url = readModel.files.first else { return }
        readError = nil; payloads = []
        do {
            let found = try QRService.read(url)
            if found.isEmpty { readError = "No QR/barcode found" } else { payloads = found }
        } catch { readError = error.localizedDescription }
    }
}
