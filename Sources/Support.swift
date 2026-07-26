import AppKit
import UniformTypeIdentifiers

/// Shared filesystem helpers for building output paths.
enum OutputPath {
    /// Returns a URL next to `source` (or in `dir` if given) named
    /// `<base><suffix>.<ext>`, bumping `-1`, `-2`… until it doesn't collide.
    static func make(for source: URL, dir: URL?, suffix: String, ext: String) -> URL {
        let folder = dir ?? source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(base)\(suffix).\(ext)")
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)\(suffix)-\(n).\(ext)")
            n += 1
        }
        return candidate
    }

    /// A fresh temp file with the given extension.
    static func temp(ext: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
    }
}

extension Int64 {
    var humanBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}

extension URL {
    var fileSize: Int64 {
        (try? resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}

/// Reveal outputs in Finder.
func revealInFinder(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting(urls)
}

extension Notification.Name {
    /// Posted by ⌘O — the visible tool's drop well opens a file panel.
    static let openFiles = Notification.Name("toolbox.openFiles")
    /// Posted by ⌘R — the visible batch tool runs.
    static let runTool = Notification.Name("toolbox.runTool")
}
