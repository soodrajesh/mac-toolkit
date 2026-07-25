import Foundation

/// Locates and invokes a Ghostscript binary for high-quality PDF compression.
/// Optional: when absent, PDFService falls back to native rasterization.
enum Ghostscript {

    enum Preset: String, CaseIterable, Identifiable {
        case screen  = "screen"   // 72 dpi  — smallest
        case ebook   = "ebook"    // 150 dpi — balanced
        case printer = "printer"  // 300 dpi — high quality
        case prepress = "prepress"
        var id: String { rawValue }
        var label: String {
            switch self {
            case .screen:   return "Screen (72 dpi, smallest)"
            case .ebook:    return "eBook (150 dpi, balanced)"
            case .printer:  return "Printer (300 dpi, high)"
            case .prepress: return "Prepress (max quality)"
            }
        }
    }

    /// Cached path to the `gs` executable, if any.
    static let path: String? = {
        let candidates = ["/opt/homebrew/bin/gs", "/usr/local/bin/gs", "/usr/bin/gs"]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        // Fall back to `which gs`.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["which", "gs"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(decoding: data, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !out.isEmpty, FileManager.default.isExecutableFile(atPath: out) { return out }
        } catch { }
        return nil
    }()

    static var isAvailable: Bool { path != nil }

    /// Runs `gs` with the pdfwrite device. Throws on failure.
    static func compress(_ input: URL, to output: URL, preset: Preset) throws {
        guard let gs = path else { throw JobError.failed("Ghostscript not found") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: gs)
        p.arguments = [
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-dPDFSETTINGS=/\(preset.rawValue)",
            "-dNOPAUSE", "-dQUIET", "-dBATCH", "-dSAFER",
            "-sOutputFile=\(output.path)",
            input.path,
        ]
        let err = Pipe()
        p.standardError = err
        p.standardOutput = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              FileManager.default.fileExists(atPath: output.path) else {
            let msg = String(decoding: err.fileHandleForReading.readDataToEndOfFile(),
                             as: UTF8.self)
            throw JobError.failed("Ghostscript failed: \(msg)")
        }
    }
}
