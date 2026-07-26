import SwiftUI

@main
struct ToolboxApp: App {
    private static let collapsedSectionsKey = "collapsedSidebarSections"

    @State private var selection: Tool = .pdfCompress
    @State private var collapsedSections: Set<String> =
        Set(UserDefaults.standard.stringArray(forKey: ToolboxApp.collapsedSectionsKey) ?? [])

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(Tool.sections, id: \.name) { section in
                        Section(isExpanded: isExpandedBinding(for: section.name)) {
                            ForEach(section.tools) { tool in
                                Label(tool.rawValue, systemImage: tool.symbol)
                                    .tag(tool)
                            }
                        } header: {
                            Text(section.name)
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
                .listStyle(.sidebar)
            } detail: {
                detail(for: selection)
                    .frame(minWidth: 560, minHeight: 460)
            }
            .navigationTitle("Toolbox")
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { NotificationCenter.default.post(name: .openFiles, object: nil) }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Tool") {
                Button("Run / Process") { NotificationCenter.default.post(name: .runTool, object: nil) }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    private func isExpandedBinding(for sectionName: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedSections.contains(sectionName) },
            set: { expanded in
                if expanded { collapsedSections.remove(sectionName) }
                else { collapsedSections.insert(sectionName) }
                UserDefaults.standard.set(Array(collapsedSections), forKey: Self.collapsedSectionsKey)
            }
        )
    }

    @ViewBuilder
    private func detail(for tool: Tool) -> some View {
        switch tool {
        case .pdfCompress: PDFCompressView()
        case .pdfMerge:    PDFMergeView()
        case .pdfSplit:    PDFSplitView()
        case .pdfPages:    PDFPagesView()
        case .pdfSecurity: PDFSecurityView()
        case .pdfSign:     PDFSignView()
        case .pdfNumbers:  PDFPageNumbersView()
        case .pdfMeta:     PDFMetadataView()
        case .imageTools:  ImageToolsView()
        case .imageEdit:   ImageEditView()
        case .blur:        BlurView()
        case .redact:      RedactView()
        case .collage:     CollageView()
        case .iconGen:     IconGeneratorView()
        case .removeBG:    RemoveBackgroundView()
        case .qr:          QRCodeView()
        case .ocr:         OCRView()
        case .videoDownload: YouTubeDownloadView()
        }
    }
}
