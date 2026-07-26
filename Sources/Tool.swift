import SwiftUI

/// Sidebar entries. Grouped by section for the NavigationSplitView sidebar.
enum Tool: String, CaseIterable, Identifiable {
    case pdfCompress = "Compress PDF"
    case pdfMerge    = "Merge PDF"
    case pdfSplit    = "Split PDF"
    case pdfPages    = "PDF Pages"
    case pdfSecurity = "PDF Security"
    case imageTools  = "Image Tools"
    case imageEdit   = "Image Editor"
    case blur        = "Blur / Pixelate"
    case redact      = "Redact"
    case collage     = "Collage"
    case iconGen     = "Icon Generator"
    case removeBG    = "Remove Background"
    case qr          = "QR Code"
    case ocr         = "OCR / Text"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pdfCompress: return "arrow.down.circle"
        case .pdfMerge:    return "arrow.triangle.merge"
        case .pdfSplit:    return "scissors"
        case .pdfPages:    return "doc.on.doc"
        case .pdfSecurity: return "lock.doc"
        case .imageTools:  return "photo"
        case .imageEdit:   return "crop.rotate"
        case .blur:        return "eye.slash"
        case .redact:      return "rectangle.fill.badge.xmark"
        case .collage:     return "square.grid.2x2"
        case .iconGen:     return "app.badge"
        case .removeBG:    return "wand.and.stars"
        case .qr:          return "qrcode"
        case .ocr:         return "text.viewfinder"
        }
    }

    var section: String {
        switch self {
        case .pdfCompress, .pdfMerge, .pdfSplit, .pdfPages, .pdfSecurity: return "PDF"
        case .imageTools, .imageEdit, .blur, .redact, .collage, .iconGen, .removeBG: return "Images"
        case .qr:  return "Utilities"
        case .ocr: return "Recognition"
        }
    }

    static var sections: [(name: String, tools: [Tool])] {
        var order: [String] = []
        var map: [String: [Tool]] = [:]
        for t in Tool.allCases {
            if map[t.section] == nil { order.append(t.section) }
            map[t.section, default: []].append(t)
        }
        return order.map { ($0, map[$0]!) }
    }
}

/// Result of a completed batch job.
struct JobResult {
    var outputs: [URL] = []
    var messages: [String] = []
    var failures: [String] = []

    var isEmpty: Bool { outputs.isEmpty && failures.isEmpty && messages.isEmpty }
}

enum JobError: LocalizedError {
    case cannotOpen(URL)
    case cannotWrite(URL)
    case emptyInput
    case badInput(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .cannotOpen(let u): return "Cannot open \(u.lastPathComponent)"
        case .cannotWrite(let u): return "Cannot write \(u.lastPathComponent)"
        case .emptyInput: return "No input files"
        case .badInput(let s): return s
        case .failed(let s): return s
        }
    }
}
