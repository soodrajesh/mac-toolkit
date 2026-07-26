import SwiftUI

/// Sidebar entries. Grouped by section for the NavigationSplitView sidebar.
enum Tool: String, CaseIterable, Identifiable {
    case pdfCompress = "Compress PDF"
    case pdfMerge    = "Merge PDF"
    case pdfSplit    = "Split PDF"
    case pdfPages    = "PDF Pages"
    case pdfOrganize = "Organize Pages"
    case pdfSecurity = "PDF Security"
    case pdfSign     = "Sign PDF"
    case pdfNumbers  = "Page Numbers"
    case pdfMeta     = "PDF Metadata"
    case pdfCrop     = "Crop / Trim Margins"
    case imageTools  = "Convert & Compress"
    case imageEdit   = "Image Editor"
    case blur        = "Blur / Pixelate"
    case redact      = "Redact"
    case collage     = "Collage"
    case iconGen     = "Icon Generator"
    case removeBG    = "Remove Background"
    case watermark   = "Watermark"
    case qr          = "Barcode / QR"
    case ocr         = "OCR / Text"
    case transcribe  = "Transcribe"
    case videoDownload = "Video Downloader"
    case videoConvert  = "Convert & Compress Video"
    case videoExtractAudio = "Extract Audio"
    case audioTrim   = "Trim Audio"
    case audioMerge  = "Merge Audio"
    case audioLoop   = "Loop Audio"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .pdfCompress: return "arrow.down.circle"
        case .pdfMerge:    return "arrow.triangle.merge"
        case .pdfSplit:    return "scissors"
        case .pdfPages:    return "doc.on.doc"
        case .pdfOrganize: return "square.grid.3x2"
        case .pdfSecurity: return "lock.doc"
        case .pdfSign:     return "signature"
        case .pdfNumbers:  return "list.number"
        case .pdfMeta:     return "tag"
        case .pdfCrop:     return "crop"
        case .imageTools:  return "photo"
        case .imageEdit:   return "crop.rotate"
        case .blur:        return "eye.slash"
        case .redact:      return "rectangle.fill.badge.xmark"
        case .collage:     return "square.grid.2x2"
        case .iconGen:     return "app.badge"
        case .removeBG:    return "wand.and.stars"
        case .watermark:   return "seal"
        case .qr:          return "qrcode"
        case .ocr:         return "text.viewfinder"
        case .transcribe:  return "waveform.and.mic"
        case .videoDownload: return "arrow.down.to.line.circle"
        case .videoConvert:  return "film"
        case .videoExtractAudio: return "speaker.wave.3"
        case .audioTrim:     return "waveform"
        case .audioMerge:    return "waveform.badge.plus"
        case .audioLoop:     return "repeat"
        }
    }

    var section: String {
        switch self {
        case .pdfCompress, .pdfMerge, .pdfSplit, .pdfPages, .pdfOrganize, .pdfSecurity, .pdfSign, .pdfNumbers, .pdfMeta, .pdfCrop: return "PDF"
        case .imageTools, .imageEdit, .blur, .redact, .collage, .iconGen, .removeBG, .watermark: return "Images"
        case .qr:  return "Utilities"
        case .ocr, .transcribe: return "Recognition"
        case .videoDownload, .videoConvert, .videoExtractAudio: return "Media"
        case .audioTrim, .audioMerge, .audioLoop: return "Audio"
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
