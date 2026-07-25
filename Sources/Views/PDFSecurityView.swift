import SwiftUI
import UniformTypeIdentifiers

struct PDFSecurityView: View {
    @StateObject private var model = JobModel(types: [.pdf])
    @State private var op: Op = .encrypt
    @State private var password = ""
    @State private var watermarkText = "CONFIDENTIAL"
    @State private var opacity = 0.3

    enum Op: String, CaseIterable, Identifiable {
        case encrypt = "Add password"
        case decrypt = "Remove password"
        case watermark = "Add watermark"
        var id: String { rawValue }
    }

    var body: some View {
        ToolScaffold(
            title: "PDF Security",
            subtitle: "Password-protect, unlock, or watermark PDFs.",
            model: model,
            runLabel: runLabel,
            onRun: run
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Action", selection: $op) {
                    ForEach(Op.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)

                switch op {
                case .encrypt, .decrypt:
                    HStack {
                        Text("Password:")
                        SecureField("password", text: $password).frame(width: 200)
                    }
                    if op == .decrypt {
                        Text("Enter the current password to produce an unlocked copy.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                case .watermark:
                    HStack {
                        Text("Text:")
                        TextField("watermark", text: $watermarkText).frame(width: 200)
                    }
                    HStack {
                        Text("Opacity: \(Int(opacity * 100))%")
                        Slider(value: $opacity, in: 0.1...0.8).frame(width: 160)
                    }
                }
            }
        }
    }

    private var runLabel: String {
        switch op {
        case .encrypt: return "Protect"; case .decrypt: return "Unlock"; case .watermark: return "Stamp"
        }
    }

    private func run() {
        let dir = model.outputDir
        let operation = op, pw = password, text = watermarkText, op10 = opacity
        if (operation == .encrypt || operation == .decrypt) && pw.isEmpty {
            model.error = "Enter a password"; return
        }
        model.run { files in
            var r = JobResult()
            for url in files {
                do {
                    switch operation {
                    case .encrypt:
                        let out = OutputPath.make(for: url, dir: dir, suffix: "-protected", ext: "pdf")
                        try PDFService.encrypt(url, password: pw, to: out); r.outputs.append(out)
                    case .decrypt:
                        let out = OutputPath.make(for: url, dir: dir, suffix: "-unlocked", ext: "pdf")
                        try PDFService.decrypt(url, password: pw, to: out); r.outputs.append(out)
                    case .watermark:
                        let out = OutputPath.make(for: url, dir: dir, suffix: "-watermarked", ext: "pdf")
                        try PDFService.watermark(url, text: text, opacity: op10, to: out); r.outputs.append(out)
                    }
                } catch {
                    r.failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return r
        }
    }
}
