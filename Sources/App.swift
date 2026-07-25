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
    }

    @ViewBuilder
    private func detail(for tool: Tool) -> some View {
        switch tool {
        case .pdfCompress: PDFCompressView()
        case .pdfMerge:    PDFMergeView()
        case .pdfSplit:    PDFSplitView()
        case .pdfPages:    PDFPagesView()
        case .pdfSecurity: PDFSecurityView()
        case .imageTools:  ImageToolsView()
        case .ocr:         OCRView()
        }
    }
}
