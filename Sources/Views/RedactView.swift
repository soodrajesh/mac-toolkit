import SwiftUI
import UniformTypeIdentifiers

struct RedactView: View {
    @StateObject private var model = JobModel(types: [.pdf, .image], multiple: false)
    @State private var isPDF = false
    @State private var pageIndex = 0
    @State private var pageCount = 1
    @State private var baseCG: CGImage?          // unredacted current page/image
    @State private var displayImage: NSImage?    // live preview (black boxes composited)
    @State private var rectsByPage: [Int: [CGRect]] = [:]
    @State private var saved: URL?
    @State private var fillColor: Color = .black
    @State private var info: [MetadataField] = []

    private var currentRects: Binding<[CGRect]> {
        Binding(get: { rectsByPage[pageIndex] ?? [] },
                set: { rectsByPage[pageIndex] = $0 })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Redact").font(.title2).bold()
                    Text("Permanently black out regions in a PDF or image — the content underneath is destroyed, not just hidden.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }
                MetadataPanel(fields: info)

                if let displayImage {
                    if isPDF && pageCount > 1 {
                        HStack {
                            Button { step(-1) } label: { Image(systemName: "chevron.left") }.disabled(pageIndex == 0)
                            Text("Page \(pageIndex + 1) of \(pageCount)")
                            Button { step(1) } label: { Image(systemName: "chevron.right") }.disabled(pageIndex >= pageCount - 1)
                            Spacer()
                            Text("Boxes on this page: \(currentRects.wrappedValue.count)").font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    RegionSelector(image: displayImage, rects: currentRects)
                        .frame(height: 380)
                        .background(RoundedRectangle(cornerRadius: 8).fill(.black.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.gray.opacity(0.25)))
                        .onChange(of: rectsByPage) { _ in updatePreview() }

                    HStack(spacing: 14) {
                        ColorPicker("Fill color", selection: $fillColor, supportsOpacity: false)
                            .fixedSize()
                            .onChange(of: fillColor) { _ in updatePreview() }
                        ForEach(Array([Color.black, .white, .gray].enumerated()), id: \.offset) { _, c in
                            Button { fillColor = c } label: {
                                Circle().fill(c).frame(width: 16, height: 16)
                                    .overlay(Circle().strokeBorder(.gray.opacity(0.5)))
                            }.buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    Text("Live preview — the filled areas are what gets permanently removed.")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Apply Redaction") { apply() }
                            .buttonStyle(.borderedProminent)
                            .disabled(totalRects == 0)
                        Button("Clear page") { rectsByPage[pageIndex] = [] }
                            .disabled(currentRects.wrappedValue.isEmpty)
                        if totalRects > 0 { Text("\(totalRects) box\(totalRects == 1 ? "" : "es") total").font(.caption).foregroundStyle(.secondary) }
                    }

                    if let saved {
                        Button { revealInFinder([saved]) } label: {
                            Label("Redacted file saved — Reveal in Finder", systemImage: "checkmark.circle.fill")
                        }.foregroundStyle(.green)
                    }
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in load() }
    }

    private var totalRects: Int { rectsByPage.values.reduce(0) { $0 + $1.count } }

    private func load() {
        rectsByPage = [:]; pageIndex = 0; saved = nil; model.error = nil
        guard let url = model.files.first else { baseCG = nil; displayImage = nil; info = []; return }
        isPDF = url.conformsTo(.pdf)
        if isPDF {
            pageCount = max(1, PDFService.pageCount(url))
            baseCG = PDFService.renderPageCGImage(url, page: 0)
            info = FileInfoService.pdfFields(url)
        } else {
            pageCount = 1
            baseCG = try? ImageService.loadCGImage(url)
            info = FileInfoService.imageFields(url)
        }
        updatePreview()
    }

    private func step(_ d: Int) {
        guard let url = model.files.first else { return }
        pageIndex = min(max(0, pageIndex + d), pageCount - 1)
        baseCG = PDFService.renderPageCGImage(url, page: pageIndex)
        updatePreview()
    }

    /// Composites the current page's black redaction boxes onto the base image.
    private func updatePreview() {
        guard let base = baseCG else { displayImage = nil; return }
        let rects = rectsByPage[pageIndex] ?? []
        let cg = rects.isEmpty ? base : (ImageEditService.redact(base, rects: rects, color: NSColor(fillColor)) ?? base)
        displayImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    private func apply() {
        guard let url = model.files.first else { return }
        model.error = nil; saved = nil
        do {
            let nsColor = NSColor(fillColor)
            if isPDF {
                let out = OutputPath.make(for: url, dir: model.outputDir, suffix: "-redacted", ext: "pdf")
                try PDFService.redact(url, rectsByPage: rectsByPage, to: out, color: nsColor)
                saved = out
            } else {
                let cg = try ImageService.loadCGImage(url)
                guard let out = ImageEditService.redact(cg, rects: rectsByPage[0] ?? [], color: nsColor) else {
                    throw JobError.failed("Could not redact")
                }
                let dst = OutputPath.make(for: url, dir: model.outputDir, suffix: "-redacted", ext: "png")
                try ImageService.write(out, to: dst, format: .png, quality: 1)
                saved = dst
            }
        } catch { model.error = error.localizedDescription }
    }
}
