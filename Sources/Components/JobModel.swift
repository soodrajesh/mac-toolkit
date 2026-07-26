import SwiftUI
import UniformTypeIdentifiers

/// Shared state for a tool: selected files, output folder, run status, result.
/// Uses ObservableObject (not @Observable) to keep the macOS 13 deployment target.
@MainActor
final class JobModel: ObservableObject {
    private static let outputKey = "lastOutputDir"

    @Published var files: [URL] = []
    @Published var outputDir: URL? {        // nil = alongside source
        didSet {
            if let p = outputDir?.path { UserDefaults.standard.set(p, forKey: Self.outputKey) }
            else { UserDefaults.standard.removeObject(forKey: Self.outputKey) }
        }
    }
    @Published var isRunning = false
    @Published var progress = 0.0           // 0…1
    @Published var status = ""
    @Published var result: JobResult?
    @Published var error: String?

    private var task: Task<Void, Never>?
    let allowedTypes: [UTType]
    let allowsMultiple: Bool

    init(types: [UTType], multiple: Bool = true) {
        self.allowedTypes = types
        self.allowsMultiple = multiple
        if let p = UserDefaults.standard.string(forKey: Self.outputKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
                outputDir = URL(fileURLWithPath: p, isDirectory: true)
            }
        }
    }

    func add(_ urls: [URL]) {
        let expanded = urls.flatMap { url -> [URL] in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                return [url]
            }
            guard let e = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]) else { return [] }
            return e.compactMap { obj -> URL? in
                guard let u = obj as? URL else { return nil }
                let isSubDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                return isSubDir ? nil : u
            }
        }
        let matching = expanded.filter { url in
            allowedTypes.contains { url.conformsTo($0) }
        }
        let toAdd = allowsMultiple ? matching : Array(matching.prefix(1))
        if !allowsMultiple { files = [] }
        for u in toAdd where !files.contains(u) { files.append(u) }
        result = nil; error = nil
    }

    func remove(_ url: URL) { files.removeAll { $0 == url } }
    func clear() { files = []; result = nil; error = nil; progress = 0; status = "" }
    func move(from source: IndexSet, to dest: Int) { files.move(fromOffsets: source, toOffset: dest) }
    func moveUp(_ url: URL) { if let i = files.firstIndex(of: url), i > 0 { files.swapAt(i, i - 1) } }
    func moveDown(_ url: URL) { if let i = files.firstIndex(of: url), i < files.count - 1 { files.swapAt(i, i + 1) } }

    /// Runs `work` off the main actor, funnelling result/error/running state.
    /// `work` should check `Task.isCancelled` between files in multi-file loops
    /// so `cancel()` can stop a batch early.
    func run(_ work: @escaping @Sendable ([URL]) throws -> JobResult) {
        runWithProgress { files, _ in try work(files) }
    }

    /// Like `run`, but `work` also receives a `report(0...1)` callback for
    /// operations where real progress (not just "done or not") is meaningful
    /// to show — e.g. a slow video export. Safe to call from any thread.
    func runWithProgress(_ work: @escaping @Sendable ([URL], @escaping @Sendable (Double) -> Void) throws -> JobResult) {
        guard !files.isEmpty else { error = "No files selected"; return }
        let input = files
        isRunning = true; error = nil; result = nil; progress = 0
        status = "Working…"
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let report: @Sendable (Double) -> Void = { p in
                Task { @MainActor [weak self] in self?.progress = min(1, max(0, p)) }
            }
            do {
                let r = try work(input, report)
                await MainActor.run {
                    guard let self else { return }
                    self.result = r; self.isRunning = false; self.progress = 1
                    self.status = Task.isCancelled ? "Cancelled" : "Done"
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.error = error.localizedDescription; self.isRunning = false
                    self.status = ""
                }
            }
        }
    }

    /// Requests cancellation of the running job. Batch loops that check
    /// `Task.isCancelled` will stop after the current file.
    func cancel() {
        task?.cancel()
    }
}

extension URL {
    func conformsTo(_ type: UTType) -> Bool {
        guard let t = try? resourceValues(forKeys: [.contentTypeKey]).contentType else {
            // Fall back to extension matching.
            return type.preferredFilenameExtension.map {
                pathExtension.lowercased() == $0
            } ?? false
        }
        return t.conforms(to: type)
    }
}
