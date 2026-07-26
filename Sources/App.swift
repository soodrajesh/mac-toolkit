import SwiftUI

@main
struct ToolboxApp: App {
    @State private var selection: Tool = .pdfCompress

    var body: some Scene {
        WindowGroup {
            NavigationSplitView {
                List(selection: $selection) {
                    ForEach(Tool.sections, id: \.name) { section in
                        Section(section.name) {
                            ForEach(section.tools) { tool in
                                Label(tool.rawValue, systemImage: tool.symbol)
                                    .tag(tool)
                            }
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
        }
    }
}
