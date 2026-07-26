import SwiftUI
import UniformTypeIdentifiers

/// One page in the working order: which page of the source it came from, an
/// additional rotation on top of whatever rotation it already had, and a
/// lazily-loaded thumbnail.
private struct PageItem: Identifiable {
    let id = UUID()
    let originalIndex: Int
    var rotation: Int = 0
    var thumbnail: NSImage?
}

/// Drag-to-reorder support for the thumbnail grid: dropping onto another cell
/// moves the dragged page to that position.
private struct PageDropDelegate: DropDelegate {
    let target: PageItem
    @Binding var pages: [PageItem]
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != target.id,
              let from = pages.firstIndex(where: { $0.id == draggingID }),
              let to = pages.firstIndex(where: { $0.id == target.id }) else { return }
        withAnimation {
            pages.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { draggingID = nil; return true }
}

struct PDFOrganizeView: View {
    @StateObject private var model = JobModel(types: [.pdf], multiple: false)
    @State private var pages: [PageItem] = []
    @State private var trash: [PageItem] = []
    @State private var draggingID: UUID?
    @State private var info: [MetadataField] = []

    private let columns = [GridItem(.adaptive(minimum: 128, maximum: 160), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header("Organize Pages",
                       "Visually reorder, rotate, or remove pages, then save as a new PDF. Drag a thumbnail to move it.")

                DropWell(model: model)
                if !model.files.isEmpty { FileList(model: model) }
                MetadataPanel(fields: info)

                if !pages.isEmpty || !trash.isEmpty {
                    if !pages.isEmpty {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(pages) { item in
                                cell(item)
                                    .onDrag { draggingID = item.id; return NSItemProvider(object: item.id.uuidString as NSString) }
                                    .onDrop(of: [.text], delegate: PageDropDelegate(target: item, pages: $pages, draggingID: $draggingID))
                            }
                        }
                    }

                    if !trash.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Removed (\(trash.count)) — tap to restore")
                                .font(.caption).foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(trash) { item in
                                        trashThumb(item)
                                    }
                                }
                            }
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Save as New PDF") { run() }
                            .buttonStyle(.borderedProminent)
                            .disabled(pages.isEmpty || model.isRunning)
                        Button("Reset") { loadPages() }
                        Spacer()
                    }
                    OutputPicker(model: model)
                    ResultBar(model: model)
                }
            }
            .padding(20)
        }
        .onChange(of: model.files) { _ in
            loadPages()
            info = model.files.first.map { FileInfoService.pdfFields($0) } ?? []
        }
    }

    // MARK: Cells

    private func cell(_ item: PageItem) -> some View {
        let idx = pages.firstIndex(where: { $0.id == item.id })
        return VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.12))
                if let thumb = item.thumbnail {
                    Image(nsImage: thumb).resizable().scaledToFit()
                        .rotationEffect(.degrees(Double(item.rotation)))
                        .padding(4)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 128, height: 165)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.gray.opacity(0.3)))
            .overlay(alignment: .topLeading) {
                Button { rotate(item) } label: { Image(systemName: "rotate.right") }
                    .buttonStyle(.borderless).controlSize(.mini)
                    .padding(4).background(.thinMaterial, in: Circle()).padding(3)
            }
            .overlay(alignment: .topTrailing) {
                Button { remove(item) } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).controlSize(.mini).foregroundStyle(.red)
                    .padding(4).background(.thinMaterial, in: Circle()).padding(3)
            }
            Text("Page \(item.originalIndex + 1)\(idx != nil ? "  ·  #\(idx! + 1)" : "")")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func trashThumb(_ item: PageItem) -> some View {
        Button { restore(item) } label: {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(Color.gray.opacity(0.1))
                    if let thumb = item.thumbnail {
                        Image(nsImage: thumb).resizable().scaledToFit()
                            .rotationEffect(.degrees(Double(item.rotation))).padding(3)
                            .opacity(0.5)
                    }
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .frame(width: 64, height: 82)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.gray.opacity(0.25)))
                Text("Page \(item.originalIndex + 1)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func rotate(_ item: PageItem) {
        guard let i = pages.firstIndex(where: { $0.id == item.id }) else { return }
        pages[i].rotation = (pages[i].rotation + 90) % 360
    }

    private func remove(_ item: PageItem) {
        guard let i = pages.firstIndex(where: { $0.id == item.id }) else { return }
        trash.append(pages.remove(at: i))
    }

    private func restore(_ item: PageItem) {
        guard let i = trash.firstIndex(where: { $0.id == item.id }) else { return }
        pages.append(trash.remove(at: i))
    }

    private func loadPages() {
        pages = []; trash = []
        guard let url = model.files.first else { return }
        let count = PDFService.pageCount(url)
        pages = (0..<count).map { PageItem(originalIndex: $0) }
        for i in 0..<count {
            Task.detached(priority: .userInitiated) {
                let thumb = PDFService.renderPageImage(url, page: i, dpi: 45)
                await MainActor.run {
                    guard model.files.first == url else { return }
                    if let idx = pages.firstIndex(where: { $0.originalIndex == i }) { pages[idx].thumbnail = thumb }
                    else if let idx = trash.firstIndex(where: { $0.originalIndex == i }) { trash[idx].thumbnail = thumb }
                }
            }
        }
    }

    private func run() {
        guard let src = model.files.first else { return }
        let dir = model.outputDir
        let order = pages.map { (originalIndex: $0.originalIndex, rotation: $0.rotation) }
        let count = order.count
        model.run { _ in
            var r = JobResult()
            let out = OutputPath.make(for: src, dir: dir, suffix: "-organized", ext: "pdf")
            try PDFService.organize(src, order: order, to: out)
            r.outputs.append(out)
            r.messages.append("\(count) page\(count == 1 ? "" : "s") → \(out.lastPathComponent)")
            return r
        }
    }

    private func header(_ t: String, _ s: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t).font(.title2).bold()
            Text(s).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
